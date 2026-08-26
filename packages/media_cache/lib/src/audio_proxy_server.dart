import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart' as dio;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'http_utils.dart';

/// Reports a proxy failure to the log.
///
/// Every upstream failure used to be swallowed into a bare
/// `Response(HttpStatus.badGateway)`, so ExoPlayer surfaced "Response code:
/// 502" and the actual cause — timeout, TLS failure, upstream 4xx — never
/// reached the log. These paths are rare by definition, so they log
/// unconditionally rather than only in debug builds.
void _logProxyFailure(String what, Object? error) {
  final message = error == null ? what : '$what: $error';
  final now = DateTime.now();

  // 同一条失败会被反复触发 —— 离线时 ExoPlayer 自己也在不停重开请求 —— 全部打
  // 出来会把日志冲成一面墙，反而盖掉真正有信息量的行。连续重复的只留第一条，
  // 恢复正常后补一句被吞掉多少次，免得「安静」和「没发生」看起来一样。
  final last = _lastFailureAt;
  if (_lastFailureMessage == message &&
      last != null &&
      now.difference(last) < const Duration(seconds: 5)) {
    _suppressedFailures += 1;
    _lastFailureAt = now;
    return;
  }
  if (_suppressedFailures > 0) {
    debugPrint('AudioProxyServer （上一条重复 $_suppressedFailures 次）');
    _suppressedFailures = 0;
  }
  _lastFailureMessage = message;
  _lastFailureAt = now;
  debugPrint('AudioProxyServer $message');
}

String? _lastFailureMessage;
DateTime? _lastFailureAt;
int _suppressedFailures = 0;

/// 这个错误是不是「连主机名都解析不出来」。
///
/// 这类失败说明设备当下压根没有可用 DNS（飞行模式、私人 DNS 配错、VPN 断了），
/// 500ms 后再问一次结果一模一样 —— 只会把一次失败拖成两秒，还把日志刷满。所以
/// 它不参与退避重试，直接失败。
///
/// 快速失败不会丢掉恢复能力：ExoPlayer 自己会重开请求，`PlayerService` 的错误恢复
/// 也还在，网络回来照样能接上，只是不在这一层空转。
///
/// 判据用的是 `Failed host lookup` 这个字符串 —— 它由 `dart:io` 生成，各平台一致；
/// errno 反而是平台相关的（Android 7、Windows 11001、Linux -2/-3），不可靠。
@visibleForTesting
bool isHostLookupFailure(Object error) {
  Object? inner = error;
  if (inner is dio.DioException) inner = inner.error;
  return inner is SocketException &&
      inner.message.contains('Failed host lookup');
}

class _StreamSource {
  /// 上游地址。为 null 表示要等第一次真正取流时再通过 [resolveUri] 解析出来
  /// （B 站的直链带时效签名，在建队列时就全部解析一遍等于开播前打几十次请求）。
  Uri? uri;

  /// 参数为 true 时要求绕过调用方自己的缓存，重新问一次上游。
  final Future<Uri?> Function(bool forceRefresh)? resolveUri;
  final Map<String, String> headers;
  final File cacheFile;

  /// 去重键（见 [AudioProxyServer._sourceKey]）。淘汰这条记录时要顺手把反查表里
  /// 的同名条目一起删掉，否则反查表会指向一个已经不存在的 token。
  final String key;

  bool _needsFresh = false;

  _StreamSource({
    this.uri,
    this.resolveUri,
    required this.headers,
    required this.cacheFile,
    required this.key,
  }) : assert(uri != null || resolveUri != null);

  /// 惰性拿到上游地址。解析结果会写回 [uri]，同一个 token 只解析一次。
  Future<Uri> ensureUri() async {
    final cached = uri;
    if (cached != null) return cached;
    final resolved = await resolveUri!(_needsFresh);
    _needsFresh = false;
    if (resolved == null) {
      throw StateError('无法解析上游音频地址');
    }
    return uri = resolved;
  }

  /// 上游返回 403 通常意味着签名过期，需要丢掉缓存的地址重新解析一次。
  void invalidate() {
    if (resolveUri == null) return;
    uri = null;
    _needsFresh = true;
  }
}

class _ByteRange {
  final int start;
  final int end;

  const _ByteRange(this.start, this.end);
}

class _ContentRange {
  final int start;
  final int end;
  final int total;

  const _ContentRange(this.start, this.end, this.total);
}

class AudioProxyServer {
  static final AudioProxyServer instance = AudioProxyServer._internal();
  AudioProxyServer._internal();

  HttpServer? _server;
  Future<void>? _starting;
  final Map<String, _StreamSource> _sources = {};

  /// 去重键 → token 的反查表。同一首歌反复注册（预热、TTL 到期重注册、播放出错
  /// 重试）必须拿回**同一个** token，否则每注册一次就多占一个槽位，几十首歌就能
  /// 把整张表冲掉一遍。
  final Map<String, String> _tokenByKey = {};

  // Cache-file paths currently being written to .tmp, so two concurrent
  // requests for the same song never interleave writes / promote a garbage file.
  final Set<String> _activeCacheWrites = {};

  // 保留的 token 上限。
  //
  // **这个值必须大于最长的播放队列**。`setAudioSources` 把整条队列的代理地址一次性
  // 交给 ExoPlayer，之后这些地址就固定在播放器的播放列表里了 —— 队列里任何一个
  // token 被淘汰，播到那首时就是 404。之前是 512，而一个完整音乐库的队列轻松到
  // 三四千首，于是**第 0 首的 token 在队列还没建完时就被自己挤掉了**，一按播放
  // 就报 Source error。
  //
  // 淘汰改成按最近使用（见 [_handleRequest]），所以正在播的那首和它周围的永远排在
  // 队尾，真到了上限也轮不到它们。每条记录只是 uri + headers + File，一万条也就
  // 十几 MB。
  static const int _maxSources = 8192;

  final dio.Dio _client = dio.Dio(
    dio.BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      // Redirects are handled manually in HttpUtils
      followRedirects: false,
      responseType: dio.ResponseType.stream,
      validateStatus: (code) => code != null && code >= 200 && code < 500,
    ),
  );

  Future<void> start() async {
    if (_server != null) return;
    // Guard against concurrent callers (e.g. warming current + next track at
    // once) each binding a separate server and leaking all but one.
    return _starting ??= _doStart();
  }

  Future<void> _doStart() async {
    try {
      _server = await shelf_io.serve(
        _handleRequest,
        InternetAddress.loopbackIPv4,
        0,
      );
    } finally {
      _starting = null;
    }
  }

  Future<void> resetSources() async {
    _sources.clear();
    _tokenByKey.clear();
  }

  /// 该 token 是否还在表里。给测试用 —— 队列里任何一个 token 被淘汰，播到那首就是
  /// 404，所以「还在不在」本身就是要断言的东西。
  @visibleForTesting
  bool hasToken(String token) => _sources.containsKey(token);

  int _tokenSeq = 0;

  String _mintToken(File cacheFile) {
    _tokenSeq += 1;
    return '${cacheFile.path.hashCode}_'
        '${DateTime.now().microsecondsSinceEpoch}_$_tokenSeq';
  }

  /// 一首歌在代理里的身份：缓存文件 + 鉴权头。
  ///
  /// 不含上游地址 —— B 站那种延迟解析的源注册时 `uri` 还是 null，等真正取流才填，
  /// 把它算进键里同一首歌会拿到两个 token。
  String _sourceKey(Map<String, String> headers, File cacheFile) {
    final pairs = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '${cacheFile.path}|${pairs.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  Future<Uri> registerSource({
    Uri? uri,
    Future<Uri?> Function(bool forceRefresh)? resolveUri,
    required Map<String, String> headers,
    required File cacheFile,
  }) async {
    await start();

    final key = _sourceKey(headers, cacheFile);
    // 同一首歌复用同一个 token。注意这里仍然**替换** _StreamSource：调用方重新
    // 注册往往正是因为要强制刷新（比如签名过期重解析），沿用旧对象会把已经作废的
    // uri 一起留下。
    //
    // 新 token 带一个自增序号。原来只有「缓存路径 hash + 微秒时间戳」，同一微秒里
    // 注册两个源（建队列时就是这样连着注册的）会撞成同一个字符串，后一个直接覆盖
    // 前一个 —— 于是两首歌共用一条上游，放出来是另一首。
    final token = _tokenByKey[key] ?? _mintToken(cacheFile);

    if (!_sources.containsKey(token) && _sources.length >= _maxSources) {
      // Map 按插入序遍历，而命中时会重新插入到队尾（见 _handleRequest），
      // 所以 keys.first 就是最久没被用过的那个。
      final evictedToken = _sources.keys.first;
      final evicted = _sources.remove(evictedToken);
      if (evicted != null) _tokenByKey.remove(evicted.key);
    }

    _tokenByKey[key] = token;
    _sources[token] = _StreamSource(
      uri: uri,
      resolveUri: resolveUri,
      headers: headers,
      cacheFile: cacheFile,
      key: key,
    );
    return Uri.parse('http://127.0.0.1:${_server!.port}/stream?token=$token');
  }

  Future<Response> _handleRequest(Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(HttpStatus.methodNotAllowed);
    }
    if (request.url.path != 'stream') {
      return Response.notFound('');
    }
    final token = request.url.queryParameters['token'];
    if (token == null) {
      if (kDebugMode) {
        debugPrint(
          'AudioProxyServer 404: missing token ${request.requestedUri}',
        );
      }
      return Response.notFound('');
    }
    final source = _sources.remove(token);
    if (source == null) {
      _logProxyFailure('404: unknown token $token', null);
      return Response.notFound('');
    }
    // 重新插入 = 移到队尾，淘汰时按最近使用而不是插入顺序挑，正在播的那首不会被挤掉。
    _sources[token] = source;

    final cacheFile = source.cacheFile;
    final completeMarker = File('${cacheFile.path}.complete');
    final rangeHeader =
        request.headers[HttpHeaders.rangeHeader] ?? request.headers['range'];

    // If fully cached, serve from file directly
    if (await cacheFile.exists() && await completeMarker.exists()) {
      return _serveFromFile(request, cacheFile, rangeHeader);
    }

    // Otherwise, proxy the stream (handling partial cache internally)
    return _proxyAndStream(request, source, rangeHeader);
  }

  Future<Response> _serveFromFile(
    Request request,
    File file,
    String? rangeHeader,
  ) async {
    final length = await file.length();
    final range = _parseRange(rangeHeader, length);
    final headers = <String, String>{
      HttpHeaders.acceptRangesHeader: 'bytes',
      HttpHeaders.contentTypeHeader: 'application/octet-stream',
    };

    if (range == null) {
      headers[HttpHeaders.contentLengthHeader] = length.toString();
      if (request.method == 'HEAD') {
        return Response(HttpStatus.ok, headers: headers);
      }
      return Response.ok(file.openRead(), headers: headers);
    }

    if (range.start >= length) {
      headers[HttpHeaders.contentRangeHeader] = 'bytes */$length';
      return Response(
        HttpStatus.requestedRangeNotSatisfiable,
        headers: headers,
      );
    }

    final end = range.end >= length ? length - 1 : range.end;
    headers[HttpHeaders.contentRangeHeader] =
        'bytes ${range.start}-$end/$length';
    headers[HttpHeaders.contentLengthHeader] = (end - range.start + 1)
        .toString();
    if (request.method == 'HEAD') {
      return Response(HttpStatus.partialContent, headers: headers);
    }
    return Response(
      HttpStatus.partialContent,
      body: file.openRead(range.start, end + 1),
      headers: headers,
    );
  }

  Future<Response> _proxyAndStream(
    Request request,
    _StreamSource source,
    String? rangeHeader,
  ) async {
    final cacheFile = source.cacheFile;
    final tmpFile = File('${cacheFile.path}.tmp');
    final requestedRange = _parseRange(rangeHeader, -1);
    // If another request is already caching this song, don't read/resume from
    // its half-written .tmp — fetch fresh and skip caching here.
    final cacheBusy = _activeCacheWrites.contains(cacheFile.path);

    int localLength = 0;
    if (!cacheBusy && await tmpFile.exists()) {
      try {
        localLength = await tmpFile.length();
      } catch (_) {
        localLength = 0;
      }
    }

    // Check if we can resume from a partial download
    // Only resume if the request starts from 0 (normal playback start)
    // and we have a non-empty partial file
    final isResumeCandidate =
        (requestedRange == null || requestedRange.start == 0) &&
        localLength > 0;

    // If resuming, adjust the range header sent to remote
    var effectiveRangeHeader = isResumeCandidate
        ? 'bytes=$localLength-'
        : rangeHeader;

    dio.Response<dio.ResponseBody> remoteResponse;
    try {
      remoteResponse = await _fetchRemoteResponse(
        source,
        effectiveRangeHeader,
        method: request.method,
      );
    } catch (e) {
      _logProxyFailure('upstream fetch failed range=$effectiveRangeHeader', e);
      return Response(HttpStatus.badGateway);
    }

    var remoteStatus = remoteResponse.statusCode ?? 0;

    // Handle edge cases where resumption might fail or be rejected

    // 1. If remote returns 404/405 for HEAD, try generic GET
    if (request.method == 'HEAD' &&
        (remoteStatus == HttpStatus.notFound ||
            remoteStatus == HttpStatus.methodNotAllowed) &&
        effectiveRangeHeader == null) {
      try {
        remoteResponse = await _fetchRemoteResponse(
          source,
          'bytes=0-0',
          method: 'GET',
        );
        remoteStatus = remoteResponse.statusCode ?? 0;
      } catch (_) {}
    }

    // 2. If remote returns 404 (Not Found) when we asked for a range, try clearing cache and fetching all
    if (remoteStatus == HttpStatus.notFound && effectiveRangeHeader != null) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      localLength = 0;
      effectiveRangeHeader = null;
      try {
        remoteResponse = await _fetchRemoteResponse(
          source,
          null,
          method: request.method,
        );
      } catch (e) {
        _logProxyFailure('upstream retry without range failed', e);
        return Response(HttpStatus.badGateway);
      }
      remoteStatus = remoteResponse.statusCode ?? 0;
    }

    // 3. If remote says Range Not Satisfiable, clear cache and retry with original range
    if (remoteStatus == HttpStatus.requestedRangeNotSatisfiable &&
        isResumeCandidate) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      localLength = 0;
      effectiveRangeHeader = rangeHeader;
      try {
        remoteResponse = await _fetchRemoteResponse(
          source,
          effectiveRangeHeader,
          method: request.method,
        );
      } catch (e) {
        _logProxyFailure('upstream range retry failed', e);
        return Response(HttpStatus.badGateway);
      }
      remoteStatus = remoteResponse.statusCode ?? 0;
    }

    // 4. Log other errors
    if (remoteStatus >= 400) {
      _logProxyFailure(
        'upstream returned $remoteStatus for '
        '${HttpUtils.redactUri(remoteResponse.realUri)}',
        null,
      );
      return Response(remoteStatus);
    }

    // 5. If Internal Server Error with range, try without range
    if (remoteResponse.statusCode == HttpStatus.internalServerError &&
        effectiveRangeHeader != null) {
      try {
        remoteResponse = await _fetchRemoteResponse(
          source,
          null,
          method: request.method,
        );
        localLength = 0;
      } catch (e) {
        _logProxyFailure('upstream retry after 500 failed', e);
        return Response(HttpStatus.badGateway);
      }
    }

    // Determine if we are actually resuming based on response
    var isResuming = false;
    if (isResumeCandidate &&
        remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange = remoteResponse.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      if (contentRange != null) {
        final parsed = _parseContentRange(contentRange);
        if (parsed != null && parsed.start == localLength) {
          isResuming = true;
        }
      }
    }

    // If we expected to resume but server didn't support it, start over
    if (isResumeCandidate && !isResuming) {
      localLength = 0;
    }

    final headers = <String, String>{};
    remoteResponse.headers.forEach((key, values) {
      if (key.toLowerCase() == 'transfer-encoding') return;
      headers[key] = values.join(',');
    });
    headers.putIfAbsent(
      HttpHeaders.contentTypeHeader,
      () => 'application/octet-stream',
    );

    var status = remoteResponse.statusCode ?? HttpStatus.ok;

    // Adjust headers for the client if we are stitching streams
    if (isResuming) {
      final remoteLen =
          int.tryParse(
            remoteResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '',
          ) ??
          0;
      final totalLen = localLength + remoteLen;
      if (totalLen > 0) {
        headers[HttpHeaders.contentLengthHeader] = totalLen.toString();
      }

      final remoteContentRange = remoteResponse.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      if (remoteContentRange != null) {
        final parsed = _parseContentRange(remoteContentRange);
        if (parsed != null) {
          // We pretend to return the full range (or 0-end) to the client
          headers[HttpHeaders.contentRangeHeader] =
              'bytes 0-${parsed.total - 1}/${parsed.total}';
          status = HttpStatus.partialContent;
        }
      }
    }

    IOSink? sink;
    var ownsCacheWrite = false;
    final canCache =
        (requestedRange == null || requestedRange.start == 0) &&
        (remoteResponse.statusCode == HttpStatus.ok ||
            remoteResponse.statusCode == HttpStatus.partialContent);

    // Logic to verify if download will be complete
    var shouldComplete = false;
    int? expectedWriteBytes;
    if (remoteResponse.statusCode == HttpStatus.ok) {
      final remoteLen = int.tryParse(
        remoteResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '',
      );
      if (remoteLen != null && remoteLen > 0) {
        shouldComplete = true;
        expectedWriteBytes = remoteLen;
      }
    } else if (remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange = remoteResponse.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      if (contentRange != null) {
        final parsed = _parseContentRange(contentRange);
        if (parsed != null) {
          if (isResuming) {
            shouldComplete = parsed.end + 1 == parsed.total;
            if (shouldComplete) {
              expectedWriteBytes = parsed.total - localLength;
            }
          } else {
            shouldComplete =
                parsed.start == 0 && parsed.end + 1 == parsed.total;
            if (shouldComplete) {
              expectedWriteBytes = parsed.total;
            }
          }
        }
      }
    }

    if (canCache && shouldComplete) {
      // Acquire the per-file cache-write lock; if another request holds it,
      // stream without caching so we never interleave .tmp writes.
      if (_activeCacheWrites.add(cacheFile.path)) {
        ownsCacheWrite = true;
        await tmpFile.parent.create(recursive: true);
        sink = tmpFile.openWrite(
          mode: isResuming ? FileMode.append : FileMode.write,
        );
      }
    }

    if (request.method == 'HEAD') {
      if (ownsCacheWrite) {
        // No body will be written for HEAD; release the lock and close sink.
        _activeCacheWrites.remove(cacheFile.path);
        try {
          await sink?.close();
        } catch (_) {}
      }
      return Response(status, headers: headers);
    }

    final responseStream = remoteResponse.data?.stream;
    if (responseStream == null) {
      _logProxyFailure('upstream returned $status with no body stream', null);
      if (ownsCacheWrite) {
        _activeCacheWrites.remove(cacheFile.path);
        try {
          await sink?.close();
        } catch (_) {}
      }
      return Response(HttpStatus.badGateway);
    }

    final remoteForward = _forwardRemoteWithCache(
      responseStream,
      sink: sink,
      canCache: canCache,
      shouldComplete: shouldComplete,
      expectedWriteBytes: expectedWriteBytes,
      tmpFile: tmpFile,
      cacheFile: cacheFile,
      ownsCacheWrite: ownsCacheWrite,
    );

    // Chain local file stream + remote stream
    final bodyStream = (isResuming && localLength > 0)
        ? _chainStreams(tmpFile.openRead(), remoteForward)
        : remoteForward;

    return Response(status, body: bodyStream, headers: headers);
  }

  Stream<List<int>> _chainStreams(
    Stream<List<int>> a,
    Stream<List<int>> b,
  ) async* {
    yield* a;
    yield* b;
  }

  Stream<List<int>> _forwardRemoteWithCache(
    Stream<List<int>> remoteStream, {
    required IOSink? sink,
    required bool canCache,
    required bool shouldComplete,
    required int? expectedWriteBytes,
    required File tmpFile,
    required File cacheFile,
    required bool ownsCacheWrite,
  }) async* {
    Object? error;
    var written = 0;
    // Use a larger buffer size (64KB) to reduce stream events and overhead
    final buffer = BytesBuilder(copy: false);
    const bufferSize = 64 * 1024;

    try {
      await for (final data in remoteStream) {
        if (data.isEmpty) continue;
        buffer.add(data);

        if (buffer.length >= bufferSize) {
          final chunk = buffer.takeBytes();
          written += chunk.length;
          sink?.add(chunk);
          yield chunk;
        }
      }

      // Yield remaining bytes
      if (buffer.isNotEmpty) {
        final chunk = buffer.takeBytes();
        written += chunk.length;
        sink?.add(chunk);
        yield chunk;
      }
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      try {
        await sink?.flush();
      } catch (_) {}
      try {
        await sink?.close();
      } catch (_) {}

      final expectedOk = expectedWriteBytes == null
          ? true
          : written == expectedWriteBytes;
      if (error == null &&
          canCache &&
          shouldComplete &&
          expectedOk &&
          await tmpFile.exists()) {
        try {
          if (await cacheFile.exists()) {
            await cacheFile.delete();
          }
        } catch (_) {}
        try {
          await tmpFile.rename(cacheFile.path);
        } catch (_) {
          // Fallback if rename fails (cross-device)
          try {
            await tmpFile.copy(cacheFile.path);
            await tmpFile.delete();
          } catch (_) {}
        }
        try {
          await File(
            '${cacheFile.path}.complete',
          ).writeAsString('1', flush: true);
        } catch (_) {}
      }
      if (ownsCacheWrite) {
        _activeCacheWrites.remove(cacheFile.path);
      }
    }
  }

  Future<dio.Response<dio.ResponseBody>> _fetchRemoteResponse(
    _StreamSource source,
    String? rangeHeader, {
    required String method,
  }) async {
    final currentHeaders = <String, dynamic>{
      ...source.headers,
      'Accept-Encoding': 'identity',
    };
    if (rangeHeader != null) {
      currentHeaders[HttpHeaders.rangeHeader] = rangeHeader;
    }

    // Retry logic for connection errors
    int retryCount = 0;
    while (true) {
      try {
        final upstream = await source.ensureUri();
        final response =
            await HttpUtils.fetchWithManualRedirect<dio.ResponseBody>(
              _client,
              upstream,
              options: dio.Options(
                headers: currentHeaders,
                responseType: dio.ResponseType.stream,
              ),
            );
        // 403 在带签名的直链上就是「地址过期了」，重新解析一次再打。
        if (response.statusCode == HttpStatus.forbidden && retryCount < 2) {
          source.invalidate();
          retryCount++;
          continue;
        }
        return response;
      } catch (e) {
        if (isHostLookupFailure(e)) {
          _logProxyFailure('upstream host lookup failed, not retrying', e);
          rethrow;
        }
        retryCount++;
        if (retryCount >= 3) {
          _logProxyFailure('upstream fetch gave up after $retryCount tries', e);
          rethrow;
        }
        _logProxyFailure(
          'upstream fetch attempt $retryCount failed, retrying',
          e,
        );
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
  }

  _ContentRange? _parseContentRange(String contentRange) {
    final parts = contentRange.split(' ');
    if (parts.length != 2) return null;
    final rangeAndTotal = parts[1].split('/');
    if (rangeAndTotal.length != 2) return null;
    final rangePart = rangeAndTotal[0];
    final total = int.tryParse(rangeAndTotal[1]) ?? -1;
    final dash = rangePart.indexOf('-');
    if (dash == -1) return null;
    final start = int.tryParse(rangePart.substring(0, dash)) ?? -1;
    final end = int.tryParse(rangePart.substring(dash + 1)) ?? -1;
    if (start < 0 || end < 0 || total <= 0) return null;
    return _ContentRange(start, end, total);
  }

  _ByteRange? _parseRange(String? rangeHeader, int totalLength) {
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) return null;
    final range = rangeHeader.substring('bytes='.length);
    final parts = range.split('-');
    if (parts.isEmpty) return null;
    if (parts[0].isEmpty) {
      final suffix = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (suffix == null || suffix <= 0) return null;
      if (totalLength <= 0) return null;
      final start = totalLength - suffix;
      return _ByteRange(start < 0 ? 0 : start, totalLength - 1);
    }

    final start = int.tryParse(parts[0]) ?? 0;
    final end = parts.length > 1 && parts[1].isNotEmpty
        ? int.tryParse(parts[1]) ?? (totalLength > 0 ? totalLength - 1 : start)
        : (totalLength > 0 ? totalLength - 1 : start);
    return _ByteRange(start, end);
  }
}
