import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart' as dio;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../core/network/http_utils.dart';
import '../models/music_entity.dart';

class _StreamSource {
  final Uri uri;
  final Map<String, String> headers;
  final File cacheFile;

  _StreamSource({
    required this.uri,
    required this.headers,
    required this.cacheFile,
  });
}

class _ByteRange {
  final int start;
  final int end;

  _ByteRange(this.start, this.end);
}

class _ContentRange {
  final int start;
  final int end;
  final int total;

  _ContentRange(this.start, this.end, this.total);
}

class AudioProxyServer {
  HttpServer? _server;
  final Map<String, _StreamSource> _sources = {};
  
  // Shared Dio client for connection pooling
  final dio.Dio _client = dio.Dio(
    dio.BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      // Validate status manually handled by HttpUtils
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

  Future<Uri> registerSource(MusicEntity song, File cacheFile) async {
    await start();
    final headers = <String, String>{
      ...?song.headers,
    };
    headers.putIfAbsent('User-Agent', () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
    final token =
        '${song.id.hashCode}_${DateTime.now().microsecondsSinceEpoch}';
    _sources[token] = _StreamSource(
      uri: Uri.parse(song.uri!),
      headers: headers,
      cacheFile: cacheFile,
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
    if (token == null || !_sources.containsKey(token)) {
      return Response.notFound('');
    }

    final source = _sources[token]!;
    final completeFile = File('${source.cacheFile.path}.complete');
    final rangeHeader = request.headers[HttpHeaders.rangeHeader] ?? request.headers['range'];

    if (await source.cacheFile.exists() && await completeFile.exists()) {
      return _serveFromCache(request, source.cacheFile, rangeHeader);
    }

    return _proxyAndStream(request, source, rangeHeader);
  }

  Future<Response> _serveFromCache(
    Request request,
    File cacheFile,
    String? rangeHeader,
  ) async {
    final length = await cacheFile.length();
    final range = _parseRange(rangeHeader, length);
    final headers = <String, String>{
      HttpHeaders.acceptRangesHeader: 'bytes',
      HttpHeaders.contentTypeHeader: 'application/octet-stream',
    };
    if (range == null) {
      if (request.method == 'HEAD') {
        headers[HttpHeaders.contentLengthHeader] = length.toString();
        return Response(HttpStatus.ok, headers: headers);
      }
      headers[HttpHeaders.contentLengthHeader] = length.toString();
      return Response.ok(
        cacheFile.openRead(),
        headers: headers,
      );
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
    headers[HttpHeaders.contentLengthHeader] =
        (end - range.start + 1).toString();
    if (request.method == 'HEAD') {
      return Response(
        HttpStatus.partialContent,
        headers: headers,
      );
    }
    return Response(
      HttpStatus.partialContent,
      body: cacheFile.openRead(range.start, end + 1),
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
    
    // Check if we can resume from a partial download
    // Only resume if the request starts from 0 (normal playback start)
    // and we have a non-empty partial file
    int localLength = 0;
    if (await tmpFile.exists()) {
      localLength = await tmpFile.length();
    }
    
    final requestedRange = _parseRange(rangeHeader, -1);
    final isResumeCandidate = (requestedRange == null || requestedRange.start == 0) && localLength > 0;
    
    // If resuming, adjust the range header sent to remote
    String? effectiveRangeHeader = rangeHeader;
    if (isResumeCandidate) {
      effectiveRangeHeader = 'bytes=$localLength-';
    }

    dio.Response<dio.ResponseBody> remoteResponse;
    try {
      remoteResponse = await _fetchRemoteResponse(source, effectiveRangeHeader);
    } catch (e) {
      return Response(HttpStatus.badGateway);
    }

    if (remoteResponse.statusCode == HttpStatus.internalServerError &&
        effectiveRangeHeader != null) {
      try {
        remoteResponse = await _fetchRemoteResponse(source, null);
        // Fallback to full download, disable resume
        localLength = 0; 
      } catch (_) {
        return Response(HttpStatus.badGateway);
      }
    }

    // Determine if we are actually resuming based on response
    bool isResuming = false;
    if (isResumeCandidate && remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange = remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final parsed = _parseContentRange(contentRange);
        if (parsed != null && parsed.start == localLength) {
          isResuming = true;
        }
      }
    }

    // If we tried to resume but server didn't support it (e.g. sent 200 OK),
    // we must discard local cache and start over
    if (isResumeCandidate && !isResuming) {
      localLength = 0;
      // Note: we don't delete tmpFile here immediately because openWrite() below will overwrite it
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

    // Update Content-Length and Content-Range for the client (player)
    // If resuming, the player thinks it's getting the full file (or 0-), 
    // but we are stitching local + remote.
    if (isResuming) {
       final remoteLen = int.tryParse(remoteResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '') ?? 0;
       final totalLen = localLength + remoteLen;
       headers[HttpHeaders.contentLengthHeader] = totalLen.toString();
       
       // If remote has Content-Range: bytes START-END/TOTAL
       // We should ideally return bytes 0-TOTAL/TOTAL
       final remoteContentRange = remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
       if (remoteContentRange != null) {
          final parsed = _parseContentRange(remoteContentRange);
          if (parsed != null) {
             headers[HttpHeaders.contentRangeHeader] = 'bytes 0-${parsed.total - 1}/${parsed.total}';
          }
       }
    }

    IOSink? sink;
    final canCache = (requestedRange == null || requestedRange.start == 0) &&
        (remoteResponse.statusCode == HttpStatus.ok ||
            remoteResponse.statusCode == HttpStatus.partialContent);

    // Logic to verify if download will be complete:
    // 1. If 200 OK -> Complete
    // 2. If 206 Partial -> 
    //    a. If resuming: start==localLength && end==total-1 -> Complete
    //    b. If not resuming: start==0 && end==total-1 -> Complete
    bool shouldComplete = false;
    if (remoteResponse.statusCode == HttpStatus.ok) {
      shouldComplete = true;
    } else if (remoteResponse.statusCode == HttpStatus.partialContent) {
      final contentRange = remoteResponse.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final parsed = _parseContentRange(contentRange);
        if (parsed != null) {
           if (isResuming) {
             shouldComplete = parsed.end + 1 == parsed.total;
           } else {
             shouldComplete = parsed.start == 0 && parsed.end + 1 == parsed.total;
           }
        }
      }
    }

    if (canCache && shouldComplete) {
      await tmpFile.parent.create(recursive: true);
      sink = tmpFile.openWrite(mode: isResuming ? FileMode.append : FileMode.write);
    }

    if (request.method == 'HEAD') {
      return Response(
        // If resuming, we effectively return 200 OK or 206 (0-) to client
        isResuming ? HttpStatus.partialContent : (remoteResponse.statusCode ?? HttpStatus.ok),
        headers: headers,
      );
    }

    final responseStream = remoteResponse.data?.stream;
    if (responseStream == null) {
      return Response(HttpStatus.badGateway);
    }

    final controller = StreamController<List<int>>();
    
    // If resuming, first pipe the local file content
    if (isResuming) {
       // We can't await here directly or we block the response return.
       // We must feed the controller asynchronously.
       Future.microtask(() async {
         try {
           final fileStream = tmpFile.openRead();
           await for (final chunk in fileStream) {
             controller.add(chunk);
           }
           // After file is done, pipe remote stream
           await _pipeRemoteStream(responseStream, controller, sink, canCache, shouldComplete, tmpFile, cacheFile);
         } catch (e, st) {
           controller.addError(e, st);
           await controller.close();
           await sink?.close();
         }
       });
    } else {
       // Standard piping
       _pipeRemoteStream(responseStream, controller, sink, canCache, shouldComplete, tmpFile, cacheFile);
    }

    return Response(
      // Client expects 206 if we send Content-Range, or 200 if full. 
      // Usually AudioPlayer handles 200 fine even for streams.
      // But if we constructed a full range response (0-end/total), 206 is safer.
      isResuming ? HttpStatus.partialContent : (remoteResponse.statusCode ?? HttpStatus.ok),
      body: controller.stream,
      headers: headers,
    );
  }

  Future<void> _pipeRemoteStream(
    Stream<List<int>> remoteStream,
    StreamController<List<int>> controller,
    IOSink? sink,
    bool canCache,
    bool shouldComplete,
    File tmpFile,
    File cacheFile,
  ) async {
    remoteStream.listen(
      (data) {
        controller.add(data);
        sink?.add(data);
      },
      onDone: () async {
        await sink?.close();
        if (canCache && shouldComplete && await tmpFile.exists()) {
          await tmpFile.rename(cacheFile.path);
          await File('${cacheFile.path}.complete').writeAsString('1');
        }
        await controller.close();
      },
      onError: (e, st) async {
        await sink?.close();
        controller.addError(e, st);
        await controller.close();
      },
      cancelOnError: true,
    );
  }

  Future<dio.Response<dio.ResponseBody>> _fetchRemoteResponse(
    _StreamSource source,
    String? rangeHeader,
  ) async {
    final currentHeaders = Map<String, dynamic>.from(source.headers);
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
    final start = int.tryParse(parts[0]) ?? 0;
    final end = parts.length > 1 && parts[1].isNotEmpty
        ? int.tryParse(parts[1]) ?? (totalLength > 0 ? totalLength - 1 : start)
        : (totalLength > 0 ? totalLength - 1 : start);
    return _ByteRange(start, end);
  }
}
