import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../http_utils.dart';

class AudioCacheService {
  static final AudioCacheService instance = AudioCacheService._internal();
  AudioCacheService._internal();

  final Map<String, Future<File?>> _inflight = {};
  final _AsyncLimiter _downloadLimiter = _AsyncLimiter(2);
  int _maxCacheBytes = 0;

  void setMaxConcurrentDownloads(int value) {
    _downloadLimiter.updateMax(value);
  }

  void setMaxCacheBytes(int value) {
    _maxCacheBytes = value < 0 ? 0 : value;
  }

  Future<File> getCacheFile({
    required String uri,
    Map<String, String>? headers,
  }) async {
    final parsed = Uri.parse(uri.trim());
    final paths = await _pathsFor(uri: parsed, headers: headers);
    return paths.complete;
  }

  Future<void> removeCachedFiles({
    required String uri,
    Map<String, String>? headers,
  }) async {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null) return;
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) return;
    try {
      final paths = await _pathsFor(uri: parsed, headers: headers);
      final tmp = File('${paths.complete.path}.tmp');
      final candidates = <File>[
        paths.complete,
        paths.part,
        paths.marker,
        tmp,
      ];
      for (final f in candidates) {
        try {
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<File?> getCompleteCachedFile({
    required String uri,
    Map<String, String>? headers,
  }) async {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null) return null;
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) return null;

    final paths = await _pathsFor(uri: parsed, headers: headers);
    if (await paths.complete.exists() && await paths.marker.exists()) {
      final size = await paths.complete.length();
      return size > 0 ? paths.complete : null;
    }
    return null;
  }

  void startBackgroundDownload({
    required String uri,
    Map<String, String>? headers,
  }) {
    unawaited(downloadToCache(uri: uri, headers: headers));
  }

  void startBackgroundDownloadSegmented({
    required String uri,
    Map<String, String>? headers,
    int maxConcurrentSegments = 4,
    int segmentSizeBytes = 2 * 1024 * 1024,
  }) {
    unawaited(
      downloadToCacheSegmented(
        uri: uri,
        headers: headers,
        maxConcurrentSegments: maxConcurrentSegments,
        segmentSizeBytes: segmentSizeBytes,
      ),
    );
  }

  Future<File?> downloadToCache({
    required String uri,
    Map<String, String>? headers,
  }) {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null) return Future.value(null);
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return Future.value(null);
    }

    final key = _hashKey('audio:${parsed.toString()}:${_headersKey(headers)}');
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final f = _downloadLimiter.run(
      () => _downloadToCacheInner(parsed, headers: headers),
    );
    _inflight[key] = f;
    f.whenComplete(() => _inflight.remove(key));
    return f;
  }

  Future<File?> downloadToCacheSegmented({
    required String uri,
    Map<String, String>? headers,
    int maxConcurrentSegments = 4,
    int segmentSizeBytes = 2 * 1024 * 1024,
  }) {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null) return Future.value(null);
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return Future.value(null);
    }

    final key = _hashKey('audio:${parsed.toString()}:${_headersKey(headers)}');
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final f = _downloadLimiter.run(
      () => _downloadToCacheSegmentedInner(
        parsed,
        headers: headers,
        maxConcurrentSegments: maxConcurrentSegments,
        segmentSizeBytes: segmentSizeBytes,
      ),
    );
    _inflight[key] = f;
    f.whenComplete(() => _inflight.remove(key));
    return f;
  }

  Future<File?> _downloadToCacheInner(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final paths = await _pathsFor(uri: uri, headers: headers);
    if (await paths.complete.exists() && await paths.marker.exists()) {
      final size = await paths.complete.length();
      return size > 0 ? paths.complete : null;
    }

    int offset = 0;
    if (await paths.part.exists()) {
      try {
        offset = await paths.part.length();
      } catch (_) {
        offset = 0;
      }
    }

    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 20),
        headers: headers,
      ),
    );

    // ignore: unused_local_variable
    final cancelToken = CancelToken();
    Response<ResponseBody> res;
    try {
      res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
          headers: {
            ...?headers,
            if (offset > 0) 'Range': 'bytes=$offset-',
            'Accept-Encoding': 'identity',
          },
        ),
      );
    } catch (_) {
      return null;
    }

    final status = res.statusCode ?? 0;
    final body = res.data;
    if (body == null) return null;
    if (status >= 400) return null;

    var mode = offset > 0 ? FileMode.append : FileMode.write;
    if (status == 200 && offset > 0) {
      offset = 0;
      mode = FileMode.write;
    }

    if (mode == FileMode.write) {
      if (await paths.part.exists()) {
        try {
          await paths.part.delete();
        } catch (_) {}
      }
    }

    final expectedTotal = _expectedTotalBytes(
      statusCode: status,
      headers: res.headers.map,
    );

    final sink = paths.part.openWrite(mode: mode);
    try {
      await for (final chunk in body.stream) {
        if (chunk.isEmpty) continue;
        sink.add(chunk);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    final currentSize = await paths.part.length();
    final isComplete = expectedTotal != null ? currentSize >= expectedTotal : false;
    if (!isComplete) return paths.part;

    if (await paths.complete.exists()) {
      try {
        await paths.complete.delete();
      } catch (_) {}
    }
    try {
      await paths.part.rename(paths.complete.path);
    } catch (_) {
      try {
        await paths.part.copy(paths.complete.path);
        await paths.part.delete();
      } catch (_) {}
    }
    try {
      await paths.marker.writeAsString('ok', flush: true);
    } catch (_) {}
    await _enforceCacheLimit();
    return paths.complete;
  }

  Future<File?> _downloadToCacheSegmentedInner(
    Uri uri, {
    Map<String, String>? headers,
    required int maxConcurrentSegments,
    required int segmentSizeBytes,
  }) async {
    final paths = await _pathsFor(uri: uri, headers: headers);
    if (await paths.complete.exists() && await paths.marker.exists()) {
      final size = await paths.complete.length();
      return size > 0 ? paths.complete : null;
    }

    final total = await _fetchContentLength(uri, headers: headers);
    if (total == null || total <= 0) {
      return _downloadToCacheInner(uri, headers: headers);
    }

    if (await paths.part.exists()) {
      try {
        await paths.part.delete();
      } catch (_) {}
    }
    await paths.part.parent.create(recursive: true);

    final raf = await paths.part.open(mode: FileMode.write);
    try {
      await raf.truncate(total);
    } finally {
      await raf.close();
    }

    final segmentCount = (total / segmentSizeBytes).ceil();
    final limiter = _AsyncLimiter(maxConcurrentSegments);
    var rangeFailed = false;

    final futures = <Future<void>>[];
    for (var i = 0; i < segmentCount; i++) {
      final start = i * segmentSizeBytes;
      final end = (start + segmentSizeBytes - 1).clamp(0, total - 1);
      futures.add(
        limiter.run(() async {
          if (rangeFailed) return;
          final ok = await _downloadRangeAndWrite(
            uri,
            headers: headers,
            start: start,
            end: end,
            part: paths.part,
          );
          if (!ok) rangeFailed = true;
        }),
      );
    }

    await Future.wait(futures);

    if (rangeFailed) {
      try {
        if (await paths.part.exists()) await paths.part.delete();
      } catch (_) {}
      return _downloadToCacheInner(uri, headers: headers);
    }

    if (await paths.complete.exists()) {
      try {
        await paths.complete.delete();
      } catch (_) {}
    }
    try {
      await paths.part.rename(paths.complete.path);
    } catch (_) {
      try {
        await paths.part.copy(paths.complete.path);
        await paths.part.delete();
      } catch (_) {}
    }
    try {
      await paths.marker.writeAsString('ok', flush: true);
    } catch (_) {}
    await _enforceCacheLimit();
    return paths.complete;
  }

  Future<bool> _downloadRangeAndWrite(
    Uri uri, {
    Map<String, String>? headers,
    required int start,
    required int end,
    required File part,
  }) async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 20),
        headers: headers,
      ),
    );

    Response<ResponseBody> res;
    try {
      res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
          headers: {
            ...?headers,
            'Range': 'bytes=$start-$end',
            'Accept-Encoding': 'identity',
          },
        ),
      );
    } catch (_) {
      return false;
    }

    final status = res.statusCode ?? 0;
    final body = res.data;
    if (body == null) return false;
    if (status != HttpStatus.partialContent) {
      try {
        await body.stream.drain();
      } catch (_) {}
      return false;
    }

    final raf = await part.open(mode: FileMode.write);
    try {
      await raf.setPosition(start);
      await for (final chunk in body.stream) {
        if (chunk.isEmpty) continue;
        await raf.writeFrom(chunk);
      }
    } catch (_) {
      return false;
    } finally {
      try {
        await raf.close();
      } catch (_) {}
    }
    return true;
  }

  Future<int?> _fetchContentLength(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 15),
        headers: headers,
      ),
    );

    try {
      final res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: Options(
          method: 'HEAD',
          responseType: ResponseType.stream,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
          headers: {
            ...?headers,
            'Accept-Encoding': 'identity',
          },
        ),
      );
      final len = _expectedTotalBytes(
        statusCode: res.statusCode ?? 0,
        headers: res.headers.map,
      );
      try {
        await res.data?.stream.drain();
      } catch (_) {}
      if (len != null && len > 0) return len;
    } catch (_) {}

    try {
      final res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: Options(
          method: 'GET',
          responseType: ResponseType.stream,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
          headers: {
            ...?headers,
            'Range': 'bytes=0-0',
            'Accept-Encoding': 'identity',
          },
        ),
      );
      final len = _expectedTotalBytes(
        statusCode: res.statusCode ?? 0,
        headers: res.headers.map,
      );
      try {
        await res.data?.stream.drain();
      } catch (_) {}
      if (len != null && len > 0) return len;
    } catch (_) {}
    return null;
  }

  int? _expectedTotalBytes({
    required int statusCode,
    required Map<String, List<String>> headers,
  }) {
    final contentRange = headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'content-range',
          orElse: () => const MapEntry('', []),
        )
        .value
        .isNotEmpty
        ? headers.entries
            .firstWhere((e) => e.key.toLowerCase() == 'content-range')
            .value
            .first
        : null;

    if (contentRange != null) {
      final match = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(contentRange);
      final total = match?.group(1);
      if (total != null && total != '*') {
        return int.tryParse(total);
      }
    }

    if (statusCode == 200) {
      final contentLength = headers.entries
          .firstWhere(
            (e) => e.key.toLowerCase() == 'content-length',
            orElse: () => const MapEntry('', []),
          )
          .value
          .isNotEmpty
          ? headers.entries
              .firstWhere((e) => e.key.toLowerCase() == 'content-length')
              .value
              .first
          : null;
      if (contentLength != null) return int.tryParse(contentLength);
    }
    return null;
  }

  String _headersKey(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final entries = headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  String _hashKey(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<_CachePaths> _pathsFor({
    required Uri uri,
    Map<String, String>? headers,
  }) async {
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(support.path, 'audio_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final ext = p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp3';
    final key = _hashKey('audio:${uri.toString()}:${_headersKey(headers)}');

    final complete = File(p.join(cacheDir.path, '$key${ext.toLowerCase()}'));
    final part = File('${complete.path}.part');
    final marker = File('${complete.path}.complete');
    return _CachePaths(complete: complete, part: part, marker: marker);
  }

  Future<int> getCacheSize() async {
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(support.path, 'audio_cache'));
    if (!await cacheDir.exists()) return 0;

    int total = 0;
    try {
      await for (final f in cacheDir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          total += await f.length();
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> clearCache() async {
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(support.path, 'audio_cache'));
    if (await cacheDir.exists()) {
      try {
        await cacheDir.delete(recursive: true);
        await cacheDir.create();
      } catch (_) {}
    }
  }

  Future<void> _enforceCacheLimit() async {
    final limit = _maxCacheBytes;
    if (limit <= 0) return;
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(support.path, 'audio_cache'));
    if (!await cacheDir.exists()) return;

    final items = <_CacheEntry>[];
    int total = 0;
    try {
      await for (final f in cacheDir.list(recursive: false, followLinks: false)) {
        if (f is! File) continue;
        final path = f.path;
        if (path.endsWith('.part') || path.endsWith('.complete')) continue;
        final stat = await f.stat();
        if (stat.size <= 0) continue;
        items.add(_CacheEntry(file: f, size: stat.size, modified: stat.modified));
        total += stat.size;
      }
    } catch (_) {
      return;
    }

    if (total <= limit) return;
    items.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in items) {
      if (total <= limit) break;
      final base = entry.file.path;
      final marker = File('$base.complete');
      final part = File('$base.part');
      try {
        if (await entry.file.exists()) {
          await entry.file.delete();
        }
      } catch (_) {}
      try {
        if (await marker.exists()) {
          await marker.delete();
        }
      } catch (_) {}
      try {
        if (await part.exists()) {
          await part.delete();
        }
      } catch (_) {}
      total -= entry.size;
    }
  }
}

class _AsyncLimiter {
  int _max;
  int _running = 0;
  final Queue<Completer<void>> _waiters = Queue();

  _AsyncLimiter(this._max);

  void updateMax(int value) {
    _max = value < 1 ? 1 : value;
    while (_running < _max && _waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }

  Future<void> _acquire() async {
    if (_running < _max) {
      _running++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
    _running++;
  }

  void _release() {
    _running--;
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) next.complete();
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }
}

class _CachePaths {
  final File complete;
  final File part;
  final File marker;

  const _CachePaths({
    required this.complete,
    required this.part,
    required this.marker,
  });
}

class _CacheEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _CacheEntry({
    required this.file,
    required this.size,
    required this.modified,
  });
}
