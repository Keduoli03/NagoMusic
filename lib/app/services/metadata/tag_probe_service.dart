import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cache/audio_cache_service.dart';

import '../http_utils.dart';
import 'tag_probe_result.dart';
import 'probe_handlers.dart';

class TagProbeService {
  static final TagProbeService instance = TagProbeService._internal();
  TagProbeService._internal();

  final AudioCacheService _audioCache = AudioCacheService.instance;
  final List<ProbeHandler> _probeHandlers = [ProgressiveHeadHandler()];

  static final Map<String, Future<TagProbeResult?>> _inflight = {};
  static final Map<String, Future<File?>> _remoteFileInflight = {};
  static final Map<String, Future<File?>> _remoteTailInflight = {};
  static final Map<String, Future<int?>> _remoteTotalInflight = {};
  static final Map<String, int?> _remoteTotalCache = {};

  Future<void> clearRemoteCaches({
    required String uri,
    Map<String, String>? headers,
  }) async {
    final u = uri.trim();
    if (u.isEmpty) return;
    final parsed = _parseSafeUri(u);
    if (parsed == null) return;
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) return;

    try {
      await _audioCache.removeCachedFiles(uri: parsed.toString(), headers: headers);
    } catch (_) {}
    try {
      await removeRemoteProbeCache(uri: parsed.toString(), headers: headers);
    } catch (_) {}

    final key = '${parsed.toString()}:${_headersKey(headers)}';
    _remoteTotalCache.remove(key);
  }

  Future<int?> remoteTotalBytes({
    required String uri,
    Map<String, String>? headers,
  }) {
    final parsed = _parseSafeUri(uri);
    if (parsed == null) return Future.value(null);
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return Future.value(null);
    }
    return _remoteTotalBytes(parsed, headers: headers);
  }

  Future<void> removeRemoteProbeCache({
    required String uri,
    Map<String, String>? headers,
  }) async {
    final parsed = _parseSafeUri(uri);
    if (parsed == null) return;
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) return;
    try {
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'tag_probe_cache'));
      final ext =
          p.extension(parsed.path).isNotEmpty ? p.extension(parsed.path) : '.mp3';
      final headerKey = _headersKey(headers);
      final name = _hashKey('remote:${parsed.toString()}:$headerKey');
      final base = File(p.join(cacheDir.path, '$name${ext.toLowerCase()}'));
      final basePart = File('${base.path}.part');
      final tail = File(p.join(cacheDir.path, '${name}_tail${ext.toLowerCase()}'));
      final tailPart = File('${tail.path}.part');
      final files = <File>[base, basePart, tail, tailPart];
      for (final f in files) {
        try {
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<TagProbeResult?> probeSongDedup({
    required String uri,
    required bool isLocal,
    Map<String, String>? headers,
    bool includeArtwork = false,
  }) {
    final headerKey = _headersKey(headers);
    final key = '${isLocal ? 'local' : 'remote'}:$uri:$includeArtwork:$headerKey';
    final exist = _inflight[key];
    if (exist != null) return exist;
    final f = probeSong(
      uri: uri,
      isLocal: isLocal,
      headers: headers,
      includeArtwork: includeArtwork,
    );
    _inflight[key] = f;
    f.whenComplete(() => _inflight.remove(key));
    return f;
  }

  Future<TagProbeResult?> probeSong({
    required String uri,
    required bool isLocal,
    Map<String, String>? headers,
    bool includeArtwork = false,
  }) async {
    final u = uri.trim();
    if (u.isEmpty) return null;
    if (isLocal) {
      final file = File(u);
      if (!await file.exists()) return null;
      return _probeFromFile(file, includeArtwork: includeArtwork);
    }

    final parsed = _parseSafeUri(u);
    if (parsed == null) return null;
    if (parsed.isScheme('file')) {
      final file = File(parsed.toFilePath());
      if (!await file.exists()) return null;
      return _probeFromFile(file, includeArtwork: includeArtwork);
    }

    if (parsed.isScheme('http') || parsed.isScheme('https')) {
      final complete = await _audioCache.getCompleteCachedFile(
        uri: parsed.toString(),
        headers: headers,
      );
      if (complete != null) {
        return _probeFromFile(complete, includeArtwork: includeArtwork);
      }
      final tmp = await _existingAudioCacheTempFile(parsed, headers: headers);
      if (tmp != null) {
        final parsedTmp = await _probeFromFile(tmp, includeArtwork: includeArtwork);
        if (parsedTmp != null) {
          if (!includeArtwork) return parsedTmp;
          if ((parsedTmp.artwork?.isNotEmpty ?? false)) return parsedTmp;
        }
      }
      final result = await _probeRemoteIncremental(
        parsed,
        headers: headers,
        includeArtwork: includeArtwork,
      );
      return result;
    }

    return null;
  }

  Future<TagProbeResult?> _probeRemoteIncremental(
    Uri uri, {
    Map<String, String>? headers,
    required bool includeArtwork,
  }) async {
    const steps = <int>[
      2 * 1024 * 1024,
      4 * 1024 * 1024,
      8 * 1024 * 1024,
    ];

    final totalBytes = await _remoteTotalBytes(uri, headers: headers);
    TagProbeResult? best;

    final cached = await _existingRemoteCacheFile(uri, headers: headers);
    if (cached != null) {
      final parsed = await _probeFromFile(cached, includeArtwork: includeArtwork);
      if (parsed != null) {
        final normalized = await _normalizeRemoteResult(
          uri: uri,
          file: cached,
          totalBytes: totalBytes,
          parsed: parsed,
        );
        if (!includeArtwork) return normalized;
        if ((normalized.artwork?.isNotEmpty ?? false)) return normalized;
        best = normalized;
      }
    }

    for (final maxBytes in steps) {
      final file = await _downloadPartialCached(
        uri,
        headers: headers,
        maxBytes: maxBytes,
      );
      if (file == null) break;
      final parsed = await _probeFromFile(file, includeArtwork: includeArtwork);
      if (parsed == null) {
        // For OGG files, partial probing often fails due to structure.
        // If we suspect it's an OGG (via extension), try downloading larger chunks or full file logic
        // But here we continue to next step (larger chunk)
        continue;
      }
      final normalized = await _normalizeRemoteResult(
        uri: uri,
        file: file,
        totalBytes: totalBytes,
        parsed: parsed,
      );
      if (!includeArtwork) return normalized;
      if ((normalized.artwork?.isNotEmpty ?? false)) return normalized;
      best = normalized;
    }

    final tail = await _downloadTailCached(
      uri,
      headers: headers,
      maxBytes: 2 * 1024 * 1024,
    );
    if (tail != null) {
      final parsed = await _probeFromFile(tail, includeArtwork: includeArtwork);
      if (parsed != null) {
        final normalized = await _normalizeRemoteResult(
          uri: uri,
          file: tail,
          totalBytes: totalBytes,
          parsed: parsed,
        );
        if (!includeArtwork) return normalized;
        if ((normalized.artwork?.isNotEmpty ?? false)) return normalized;
        best = best ?? normalized;
      }
    }
    
    // Check special handlers for fallback (e.g. OGG full download)
    for (final handler in _probeHandlers) {
      if (handler.canHandle(uri.path)) {
        final res = await handler.probe(
          uri: uri,
          headers: headers,
          includeArtwork: includeArtwork,
          totalBytes: totalBytes,
          currentBest: best,
          audioCache: _audioCache,
          prober: _probeFromFile,
          downloadPartial: (maxBytes) => _downloadPartialCached(
            uri,
            headers: headers,
            maxBytes: maxBytes,
          ),
        );
        if (res != null) return res;
      }
    }

    return best;
  }

  Future<int?> _remoteTotalBytes(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    final key = '${uri.toString()}:${_headersKey(headers)}';
    final cached = _remoteTotalCache[key];
    if (cached != null && cached > 0) return Future.value(cached);
    final inflight = _remoteTotalInflight[key];
    if (inflight != null) return inflight;
    final f = _remoteTotalBytesInner(uri, headers: headers);
    _remoteTotalInflight[key] = f;
    f.whenComplete(() => _remoteTotalInflight.remove(key));
    return f;
  }

  Future<int?> _remoteTotalBytesInner(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final dio = Dio(
      BaseOptions(
        followRedirects: false,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        connectTimeout: const Duration(seconds: 10),
        headers: headers,
        validateStatus: (code) => code != null && code >= 200 && code < 500,
      ),
    );

    int? fromHeaders(Headers h) {
      final contentRange = h.value('content-range');
      if (contentRange != null && contentRange.isNotEmpty) {
        final match =
            RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(contentRange);
        final total = match?.group(1);
        if (total != null && total != '*') {
          return int.tryParse(total);
        }
      }
      final contentLength = h.value('content-length');
      if (contentLength != null && contentLength.isNotEmpty) {
        return int.tryParse(contentLength);
      }
      return null;
    }

    try {
      final res = await HttpUtils.fetchWithManualRedirect<void>(
        dio,
        uri,
        options: Options(
          method: 'HEAD',
          headers: {
            ...?headers,
            'Accept-Encoding': 'identity',
          },
        ),
      );
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 400) {
        final total = fromHeaders(res.headers);
        if (total != null && total > 0) {
          final key = '${uri.toString()}:${_headersKey(headers)}';
          _remoteTotalCache[key] = total;
          return total;
        }
      }
    } catch (_) {}

    try {
      final res = await HttpUtils.fetchWithManualRedirect<void>(
        dio,
        uri,
        options: Options(
          method: 'GET',
          responseType: ResponseType.stream,
          headers: {
            ...?headers,
            'Range': 'bytes=0-0',
            'Accept-Encoding': 'identity',
          },
        ),
      );
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 400) {
        final total = fromHeaders(res.headers);
        if (total != null && total > 0) {
          final key = '${uri.toString()}:${_headersKey(headers)}';
          _remoteTotalCache[key] = total;
          return total;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<TagProbeResult> _normalizeRemoteResult({
    required Uri uri,
    required File file,
    required int? totalBytes,
    required TagProbeResult parsed,
  }) async {
    int size = 0;
    try {
      size = await file.length();
    } catch (_) {
      size = 0;
    }

    final format = (parsed.format ?? '').trim().toUpperCase();
    final isProbablyPartial = totalBytes != null && totalBytes > 0 && size > 0
        ? size < totalBytes
        : false;

    final keepDurationEvenIfPartial = format == 'FLAC' || format == 'WAV';
    int? durationMs = parsed.durationMs;

    if (isProbablyPartial && !keepDurationEvenIfPartial) {
      final total = totalBytes;
      final bitrate = parsed.bitrate;
      if (bitrate != null && bitrate > 0) {
        final estimatedMs = ((total * 8) * 1000 / bitrate).round();
        if (durationMs == null || durationMs <= 0) {
          durationMs = estimatedMs;
        } else {
          final expectedBytes = ((durationMs / 1000.0) * bitrate / 8.0);
          final ratio = expectedBytes <= 0 ? 0 : (expectedBytes / total);
          if (ratio < 0.6 || ratio > 1.6) {
            durationMs = estimatedMs;
          }
        }
      } else {
        durationMs = null;
      }
    }

    if (durationMs == parsed.durationMs) return parsed;

    return TagProbeResult(
      title: parsed.title,
      artist: parsed.artist,
      album: parsed.album,
      durationMs: durationMs,
      bitrate: parsed.bitrate,
      sampleRate: parsed.sampleRate,
      fileSize: parsed.fileSize,
      format: parsed.format,
      artwork: parsed.artwork,
      lyrics: parsed.lyrics,
    );
  }

  Future<TagProbeResult?> _probeFromFile(
    File file, {
    required bool includeArtwork,
  }) async {
    try {
      final stat = await file.stat();
      final meta = readMetadata(file, getImage: includeArtwork);

      Uint8List? artwork;
      if (includeArtwork && meta.pictures.isNotEmpty) {
        final bytes = meta.pictures.first.bytes;
        if (bytes.isNotEmpty) artwork = bytes;
      }

      final lyrics = _normalizeLyrics(meta.lyrics);
      var ext = p.extension(file.path).replaceAll('.', '').toUpperCase();
      // Handle .0gg typo or variation as OGG
      if (ext == '0GG') ext = 'OGG';
      
      final format = ext.isNotEmpty ? ext : null;

      return TagProbeResult(
        title: _nonEmpty(meta.title),
        artist: _nonEmpty(meta.artist),
        album: _nonEmpty(meta.album),
        durationMs: meta.duration?.inMilliseconds,
        bitrate: meta.bitrate,
        sampleRate: meta.sampleRate,
        fileSize: stat.size,
        format: format,
        artwork: artwork,
        lyrics: lyrics,
      );
    } catch (_) {
      return null;
    }
  }

  String? _nonEmpty(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? null : t;
  }

  String? _normalizeLyrics(String? raw) {
    final t = (raw ?? '').replaceFirst(RegExp('^\uFEFF'), '').trim();
    if (t.isEmpty) return null;
    final collapsed = _collapseAdjacent(t);
    final deduped = _collapseRepeated(collapsed);
    final out = deduped.trim();
    return out.isEmpty ? null : out;
  }

  String _collapseAdjacent(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.length < 2) return content;
    final out = <String>[];
    String? last;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        out.add(line);
        last = null;
        continue;
      }
      if (t == last) continue;
      out.add(line);
      last = t;
    }
    return out.join('\n');
  }

  String _collapseRepeated(String content) {
    final t = content.trim().replaceFirst(RegExp('^\uFEFF'), '');
    if (t.isEmpty) return content;
    final lines = t.split(RegExp(r'\r?\n'));
    final check = lines.map((e) => e.trim()).toList();
    final n = lines.length;
    if (n < 2) return content;
    final pi = List<int>.filled(n, 0);
    for (int i = 1; i < n; i++) {
      var j = pi[i - 1];
      while (j > 0 && check[i] != check[j]) {
        j = pi[j - 1];
      }
      if (check[i] == check[j]) {
        j++;
      }
      pi[i] = j;
    }
    final period = n - pi[n - 1];
    if (period > 0 && n % period == 0 && n ~/ period >= 2) {
      return lines.sublist(0, period).join('\n');
    }
    return content;
  }

  String _repairUrlForBrokenPercentEscapes(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    final sb = StringBuffer();

    bool isWs(int cu) =>
        cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;
    bool isHex(int cu) =>
        (cu >= 0x30 && cu <= 0x39) ||
        (cu >= 0x41 && cu <= 0x46) ||
        (cu >= 0x61 && cu <= 0x66);

    var i = 0;
    while (i < s.length) {
      final cu = s.codeUnitAt(i);
      if (cu == 0x25) {
        sb.writeCharCode(cu);
        i += 1;
        var got = 0;
        while (i < s.length && got < 2) {
          final next = s.codeUnitAt(i);
          if (isWs(next)) {
            i += 1;
            continue;
          }
          if (!isHex(next)) break;
          sb.writeCharCode(next);
          got += 1;
          i += 1;
        }
        continue;
      }
      if (cu == 0x0A || cu == 0x0D || cu == 0x09) {
        i += 1;
        continue;
      }
      if (cu == 0x20) {
        sb.write('%20');
        i += 1;
        continue;
      }
      sb.writeCharCode(cu);
      i += 1;
    }
    return sb.toString();
  }

  Uri? _parseSafeUri(String uriStr) {
    final raw = _repairUrlForBrokenPercentEscapes(uriStr);
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw) ?? Uri.tryParse(Uri.encodeFull(raw));
    if (parsed == null) return null;
    if (!(parsed.isScheme('http') || parsed.isScheme('https'))) return parsed;
    String decodeRepeatedly(String input) {
      var cur = input;
      for (var i = 0; i < 4; i++) {
        try {
          final next = Uri.decodeComponent(cur);
          if (next == cur) break;
          cur = next;
        } catch (_) {
          break;
        }
      }
      return cur;
    }

    final segments = parsed.pathSegments.map((seg) {
      if (seg.isEmpty) return seg;
      return decodeRepeatedly(seg);
    }).toList();
    return parsed.replace(pathSegments: segments);
  }

  String _headersKey(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final entries = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
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

  Future<File?> _existingRemoteCacheFile(
    Uri uri, {
    Map<String, String>? headers,
    bool tail = false,
  }) async {
    try {
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'tag_probe_cache'));
      final ext =
          p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp3';
      final headerKey = _headersKey(headers);
      final name = _hashKey('remote:${uri.toString()}:$headerKey');
      final suffix = tail ? '_tail' : '';
      final out = File(p.join(cacheDir.path, '$name$suffix${ext.toLowerCase()}'));
      if (!await out.exists()) return null;
      final size = await out.length();
      if (size <= 0) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _existingAudioCacheTempFile(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'audio_cache'));
      final ext =
          p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp3';
      final headerKey = _headersKey(headers);
      final name = _hashKey('audio:${uri.toString()}:$headerKey');
      final complete = File(p.join(cacheDir.path, '$name${ext.toLowerCase()}'));

      final tmp = File('${complete.path}.tmp');
      if (await tmp.exists()) {
        final size = await tmp.length();
        if (size > 0) return tmp;
      }

      final part = File('${complete.path}.part');
      if (await part.exists()) {
        final size = await part.length();
        if (size > 0) return part;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _downloadPartialCached(
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
  }) async {
    final headerKey = _headersKey(headers);
    final key = 'remote:${uri.toString()}:$headerKey:$maxBytes';
    final inflight = _remoteFileInflight[key];
    if (inflight != null) return inflight;
    final f = _downloadPartialCachedInner(
      uri,
      headers: headers,
      maxBytes: maxBytes,
    );
    _remoteFileInflight[key] = f;
    f.whenComplete(() => _remoteFileInflight.remove(key));
    return f;
  }

  Future<File?> _downloadPartialCachedInner(
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
  }) async {
    try {
      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'tag_probe_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final ext =
          p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp3';
      final headerKey = _headersKey(headers);
      final name = _hashKey('remote:${uri.toString()}:$headerKey');
      final out = File(p.join(cacheDir.path, '$name${ext.toLowerCase()}'));
      final tmp = File('${out.path}.part');

      int currentSize = 0;
      if (await out.exists()) {
        try {
          currentSize = await out.length();
        } catch (_) {
          currentSize = 0;
        }
      }

      if (currentSize >= maxBytes) return out;

      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.stream,
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          connectTimeout: const Duration(seconds: 15),
          headers: headers,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );

      final start = currentSize < 0 ? 0 : currentSize;
      final end = maxBytes - 1;
      final range = 'bytes=$start-$end';
      final cancelToken = CancelToken();
      Response<ResponseBody> res;
      try {
        res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
          dio,
          uri,
          cancelToken: cancelToken,
          options: Options(
            method: 'GET',
            responseType: ResponseType.stream,
            headers: {
              ...?headers,
              'Range': range,
              'Accept-Encoding': 'identity',
            },
          ),
        );
      } catch (_) {
        return currentSize > 0 ? out : null;
      }

      final status = res.statusCode ?? 0;
      final body = res.data;
      if (body == null) return currentSize > 0 ? out : null;
      if (status >= 400) return currentSize > 0 ? out : null;

      var effectiveStart = start;
      var mode = effectiveStart == 0 ? FileMode.write : FileMode.append;
      var target = out;
      if (status == 200) {
        effectiveStart = 0;
        mode = FileMode.write;
      }
      if (mode == FileMode.write) {
        target = tmp;
      }

      final remaining = maxBytes - effectiveStart;
      if (remaining <= 0) return out;

      if (target == tmp && await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }

      final sink = target.openWrite(mode: mode);
      var written = 0;
      try {
        await for (final chunk in body.stream) {
          if (chunk.isEmpty) continue;
          final left = remaining - written;
          if (left <= 0) {
            cancelToken.cancel();
            break;
          }
          if (chunk.length <= left) {
            sink.add(chunk);
            written += chunk.length;
          } else {
            sink.add(chunk.sublist(0, left));
            written += left;
            cancelToken.cancel();
            break;
          }
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
        } else {
          rethrow;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (target == tmp) {
        final sizeNow = await tmp.length();
        if (sizeNow <= 0) return null;
        if (await out.exists()) {
          try {
            await out.delete();
          } catch (_) {}
        }
        try {
          await tmp.rename(out.path);
        } catch (_) {
          try {
            await tmp.copy(out.path);
            await tmp.delete();
          } catch (_) {}
        }
      }

      final sizeNow = await out.length();
      if (sizeNow <= 0) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _downloadTailCached(
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
  }) async {
    final headerKey = _headersKey(headers);
    final key = 'remote_tail:${uri.toString()}:$headerKey:$maxBytes';
    final inflight = _remoteTailInflight[key];
    if (inflight != null) return inflight;
    final f = _downloadTailCachedInner(uri, headers: headers, maxBytes: maxBytes);
    _remoteTailInflight[key] = f;
    f.whenComplete(() => _remoteTailInflight.remove(key));
    return f;
  }

  Future<File?> _downloadTailCachedInner(
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
  }) async {
    try {
      final existing = await _existingRemoteCacheFile(uri, headers: headers, tail: true);
      if (existing != null) return existing;

      final support = await getApplicationSupportDirectory();
      final cacheDir = Directory(p.join(support.path, 'tag_probe_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final ext =
          p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp3';
      final headerKey = _headersKey(headers);
      final name = _hashKey('remote:${uri.toString()}:$headerKey');
      final out = File(p.join(cacheDir.path, '${name}_tail${ext.toLowerCase()}'));
      final tmp = File('${out.path}.part');

      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.stream,
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          connectTimeout: const Duration(seconds: 15),
          headers: headers,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );

      final cancelToken = CancelToken();
      Response<ResponseBody> res;
      try {
        res = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
          dio,
          uri,
          cancelToken: cancelToken,
          options: Options(
            method: 'GET',
            responseType: ResponseType.stream,
            headers: {
              ...?headers,
              'Range': 'bytes=-$maxBytes',
              'Accept-Encoding': 'identity',
            },
          ),
        );
      } catch (_) {
        return null;
      }

      final body = res.data;
      if (body == null) return null;
      final status = res.statusCode ?? 0;
      if (status >= 400) return null;
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }

      final sink = tmp.openWrite(mode: FileMode.write);
      var written = 0;
      try {
        await for (final chunk in body.stream) {
          if (chunk.isEmpty) continue;
          final left = maxBytes - written;
          if (left <= 0) {
            cancelToken.cancel();
            break;
          }
          if (chunk.length <= left) {
            sink.add(chunk);
            written += chunk.length;
          } else {
            sink.add(chunk.sublist(0, left));
            written += left;
            cancelToken.cancel();
            break;
          }
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
        } else {
          rethrow;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final sizeNow = await tmp.length();
      if (sizeNow <= 0) return null;
      if (await out.exists()) {
        try {
          await out.delete();
        } catch (_) {}
      }
      try {
        await tmp.rename(out.path);
      } catch (_) {
        try {
          await tmp.copy(out.path);
          await tmp.delete();
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
