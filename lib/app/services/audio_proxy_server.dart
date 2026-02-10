import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart' as dio;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'http_utils.dart';

class _StreamSource {
  final Uri uri;
  final Map<String, String> headers;
  final File cacheFile;

  const _StreamSource({
    required this.uri,
    required this.headers,
    required this.cacheFile,
  });
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
  final Map<String, _StreamSource> _sources = {};

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
    _server = await shelf_io.serve(
      _handleRequest,
      InternetAddress.loopbackIPv4,
      0,
    );
  }

  Future<void> resetSources() async {
    _sources.clear();
  }

  Future<Uri> registerSource({
    required Uri uri,
    required Map<String, String> headers,
    required File cacheFile,
  }) async {
    await start();
    // Create a unique token based on cache path and time to prevent collisions
    final token = '${cacheFile.path.hashCode}_${DateTime.now().microsecondsSinceEpoch}';
    _sources[token] = _StreamSource(uri: uri, headers: headers, cacheFile: cacheFile);
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
        debugPrint('AudioProxyServer 404: missing token ${request.requestedUri}');
      }
      return Response.notFound('');
    }
    final source = _sources[token];
    if (source == null) {
      if (kDebugMode) {
        debugPrint('AudioProxyServer 404: unknown token $token');
      }
      return Response.notFound('');
    }

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
      return Response(HttpStatus.requestedRangeNotSatisfiable, headers: headers);
    }

    final end = range.end >= length ? length - 1 : range.end;
    headers[HttpHeaders.contentRangeHeader] = 'bytes ${range.start}-$end/$length';
    headers[HttpHeaders.contentLengthHeader] = (end - range.start + 1).toString();
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

    int localLength = 0;
    if (await tmpFile.exists()) {
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
        (requestedRange == null || requestedRange.start == 0) && localLength > 0;
    
    // If resuming, adjust the range header sent to remote
    var effectiveRangeHeader =
        isResumeCandidate ? 'bytes=$localLength-' : rangeHeader;

    dio.Response<dio.ResponseBody> remoteResponse;
    try {
      remoteResponse = await _fetchRemoteResponse(
        source,
        effectiveRangeHeader,
        method: request.method,
      );
    } catch (_) {
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
      } catch (_) {
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
      } catch (_) {
        return Response(HttpStatus.badGateway);
      }
      remoteStatus = remoteResponse.statusCode ?? 0;
    }

    // 4. Log other errors
    if (remoteStatus >= 400) {
      if (kDebugMode) {
        final real = remoteResponse.realUri;
        debugPrint(
          'AudioProxyServer remote $remoteStatus: ${real.toString()}',
        );
      }
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
      } catch (_) {
        return Response(HttpStatus.badGateway);
      }
    }

    // Determine if we are actually resuming based on response
    var isResuming = false;
    if (isResumeCandidate &&
        remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange =
          remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
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
      final remoteLen = int.tryParse(
            remoteResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '',
          ) ??
          0;
      final totalLen = localLength + remoteLen;
      if (totalLen > 0) {
        headers[HttpHeaders.contentLengthHeader] = totalLen.toString();
      }

      final remoteContentRange =
          remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
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
    final canCache = (requestedRange == null || requestedRange.start == 0) &&
        (remoteResponse.statusCode == HttpStatus.ok ||
            remoteResponse.statusCode == HttpStatus.partialContent);

    // Logic to verify if download will be complete
    var shouldComplete = false;
    int? expectedWriteBytes;
    if (remoteResponse.statusCode == HttpStatus.ok) {
      final remoteLen =
          int.tryParse(remoteResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '');
      if (remoteLen != null && remoteLen > 0) {
        shouldComplete = true;
        expectedWriteBytes = remoteLen;
      }
    } else if (remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange =
          remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final parsed = _parseContentRange(contentRange);
        if (parsed != null) {
          if (isResuming) {
            shouldComplete = parsed.end + 1 == parsed.total;
            if (shouldComplete) {
              expectedWriteBytes = parsed.total - localLength;
            }
          } else {
            shouldComplete = parsed.start == 0 && parsed.end + 1 == parsed.total;
            if (shouldComplete) {
              expectedWriteBytes = parsed.total;
            }
          }
        }
      }
    }

    if (canCache && shouldComplete) {
      await tmpFile.parent.create(recursive: true);
      sink = tmpFile.openWrite(mode: isResuming ? FileMode.append : FileMode.write);
    }

    if (request.method == 'HEAD') {
      return Response(status, headers: headers);
    }

    final responseStream = remoteResponse.data?.stream;
    if (responseStream == null) return Response(HttpStatus.badGateway);

    final remoteForward = _forwardRemoteWithCache(
      responseStream,
      sink: sink,
      canCache: canCache,
      shouldComplete: shouldComplete,
      expectedWriteBytes: expectedWriteBytes,
      tmpFile: tmpFile,
      cacheFile: cacheFile,
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
  }) async* {
    Object? error;
    var written = 0;
    try {
      await for (final data in remoteStream) {
        if (data.isEmpty) continue;
        written += data.length;
        sink?.add(data);
        yield data;
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

      final expectedOk =
          expectedWriteBytes == null ? true : written == expectedWriteBytes;
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
          await File('${cacheFile.path}.complete').writeAsString('1', flush: true);
        } catch (_) {}
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
        return await HttpUtils.fetchWithManualRedirect<dio.ResponseBody>(
          _client,
          source.uri,
          options: dio.Options(
            headers: currentHeaders,
            responseType: dio.ResponseType.stream,
          ),
        );
      } catch (e) {
        retryCount++;
        if (retryCount >= 3) rethrow;
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
