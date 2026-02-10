import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../http_utils.dart';

class AudioCacheService {
  static final AudioCacheService instance = AudioCacheService._internal();
  AudioCacheService._internal();

  final Map<String, Future<File?>> _inflight = {};

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

    final f = _downloadToCacheInner(parsed, headers: headers);
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
    return paths.complete;
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
