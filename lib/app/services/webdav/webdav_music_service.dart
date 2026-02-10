import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../state/song_state.dart';
import '../db/dao/song_dao.dart';
import '../metadata/tag_probe_service.dart';
import '../metadata/tag_probe_result.dart';
import 'webdav_source_repository.dart';

class WebDavScanProgress {
  final int processed;
  final int added;
  final int total;

  const WebDavScanProgress({
    required this.processed,
    required this.added,
    required this.total,
  });
}

class WebDavScanResult {
  final int processed;
  final int added;

  const WebDavScanResult({required this.processed, required this.added});
}

class WebDavDirectory {
  final String name;
  final String path;

  const WebDavDirectory({required this.name, required this.path});
}

class WebDavMusicService {
  final SongDao _songDao = SongDao();
  final TagProbeService _tagProbe = TagProbeService.instance;
  final WebDavSourceRepository _repo = WebDavSourceRepository.instance;

  static const _audioExts = {
    '.mp3',
    '.flac',
    '.wav',
    '.m4a',
    '.ogg',
    '.aac',
    '.opus',
  };

  Future<bool> testConnection(WebDavSource source) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) return false;
    final headers = _repo.buildHeaders(source);
    try {
      final client = webdav.newClient(
        endpoint,
        user: '',
        password: '',
        debug: kDebugMode,
      );
      client.setHeaders(headers);
      final searchPath = _normalizeWebDavPath(source.path.trim().isEmpty ? '/' : source.path);
      await client.readDir(searchPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<WebDavDirectory>> listDirectories({
    required WebDavSource source,
    required String path,
  }) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) return const [];
    final headers = _repo.buildHeaders(source);
    final entries = await _listEntriesStrict(
      endpoint: endpoint,
      path: _normalizeWebDavPath(path),
      headers: headers,
    );

    final dirs = entries
        .where((e) => (e.isDir ?? false) == true)
        .map((e) {
          final rawPath = (e.path ?? '').toString();
          final normalized = _normalizeWebDavPath(rawPath);
          final name = p.basename(normalized);
          return WebDavDirectory(name: name.isEmpty ? normalized : name, path: normalized);
        })
        .where((d) => d.path.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return dirs;
  }

  Future<WebDavScanResult> scan({
    required WebDavSource source,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<WebDavScanProgress> onProgress,
  }) async {
    final endpoint = source.endpoint.trim();
    if (endpoint.isEmpty) {
      return const WebDavScanResult(processed: 0, added: 0);
    }

    final pathsToScan = source.includeFolders.isNotEmpty
        ? source.includeFolders
        : [(source.path.trim().isEmpty ? '/' : source.path.trim())];
    final exclude = source.excludeFolders.map((e) => _normalizeWebDavPath(e)).toList();
    final visited = <String>{};
    final headers = _repo.buildHeaders(source);
    final seenFiles = <String>{};

    var discovered = 0;
    onProgress(const WebDavScanProgress(processed: 0, added: 0, total: 0));

    final collected = <SongEntity>[];
    for (final path in pathsToScan) {
      if (isCancelled()) break;
      await _scanRecursive(
        source: source,
        endpoint: endpoint,
        path: _normalizeWebDavPath(path),
        excludeFolders: exclude,
        visited: visited,
        headers: headers,
        isCancelled: isCancelled,
        onFile: (href) {
          var key = href.trim();
          if (key.isEmpty) return;
          try {
            key = Uri.parse(key).toString();
          } catch (_) {}
          if (seenFiles.contains(key)) return;
          seenFiles.add(key);

          discovered += 1;
          
          // Decode the URI for display/storage if possible
          var displayUri = href;
          // Iteratively decode to handle double/triple encoding (e.g. %2520 -> %20 -> space)
          // We want the stored URI to be human-readable (no percent encoding)
          for (var i = 0; i < 4; i++) {
             try {
                final decoded = Uri.decodeFull(displayUri);
                if (decoded == displayUri) break;
                displayUri = decoded;
             } catch (_) {
                break;
             }
          }

          final title = _webDavNameFromHref(displayUri);
          final album = _webDavAlbumFromHref(displayUri);
          
          collected.add(
            SongEntity(
              id: href, // Keep original href as ID for stability
              title: title.isNotEmpty ? title : '未知标题',
              artist: source.name.trim().isNotEmpty ? source.name.trim() : '云端',
              album: album.isNotEmpty ? album : null,
              uri: displayUri, // Store decoded URI for readability
              isLocal: false,
              headersJson: jsonEncode(headers),
              sourceId: source.id,
              tagsParsed: false,
            ),
          );
          onProgress(WebDavScanProgress(processed: discovered, added: 0, total: 0));
        },
      );
    }

    if (isCancelled()) {
      return WebDavScanResult(processed: discovered, added: 0);
    }

    final existingList = await _songDao.fetchAll(sourceId: source.id);
    final existingMap = {for (final s in existingList) s.id: s};

    final bool shouldScrape = source.scrapeTagsOnScan;
    final enriched = shouldScrape
        ? await _enrichMetadata(
            songs: collected,
            headers: headers,
            existingMap: existingMap,
            isCancelled: isCancelled,
            onProgress: (_) {},
          )
        : collected
            .map((s) => _mergeWithExisting(
                  base: s,
                  meta: null,
                  existing: existingMap[s.id],
                ))
            .toList();

    if (isCancelled()) {
      return WebDavScanResult(processed: discovered, added: 0);
    }

    await _songDao.deleteBySource(source.id);
    final added = await _songDao.upsertSongs(enriched);
    onProgress(WebDavScanProgress(processed: discovered, added: added, total: discovered));
    return WebDavScanResult(processed: discovered, added: added);
  }

  Future<void> _scanRecursive({
    required WebDavSource source,
    required String endpoint,
    required String path,
    required List<String> excludeFolders,
    required Set<String> visited,
    required Map<String, String> headers,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<String> onFile,
  }) async {
    if (isCancelled()) return;
    if (visited.contains(path)) return;
    visited.add(path);

    if (_shouldExclude(path, excludeFolders)) return;

    await Future.delayed(const Duration(milliseconds: 80));

    final entries = await _listEntries(
      endpoint: endpoint,
      path: path,
      headers: headers,
    );

    for (final e in entries) {
      if (isCancelled()) break;
      if ((e.isDir ?? false) == true) {
        final childPath = _normalizeWebDavPath(e.path ?? '');
        if (childPath == path) continue;
        await _scanRecursive(
          source: source,
          endpoint: endpoint,
          path: childPath,
          excludeFolders: excludeFolders,
          visited: visited,
          headers: headers,
          isCancelled: isCancelled,
          onFile: onFile,
        );
        continue;
      }
      final href = _normalizeWebDavHref(e.path ?? '', endpoint);
      if (!_isAudioFile(href)) continue;
      onFile(href);
    }
  }

  Future<List<webdav.File>> _listEntries({
    required String endpoint,
    required String path,
    required Map<String, String> headers,
  }) async {
    try {
      return await _listEntriesStrict(
        endpoint: endpoint,
        path: path,
        headers: headers,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<webdav.File>> _listEntriesStrict({
    required String endpoint,
    required String path,
    required Map<String, String> headers,
  }) async {
    final client = webdav.newClient(
      endpoint,
      user: '',
      password: '',
      debug: kDebugMode,
    );
    client.setHeaders(headers);

    var searchPath = path.trim().isEmpty ? '/' : path.trim();
    if (!searchPath.startsWith('/')) {
      searchPath = '/$searchPath';
    }
    return client.readDir(searchPath);
  }

  Future<List<SongEntity>> _enrichMetadata({
    required List<SongEntity> songs,
    required Map<String, String> headers,
    required Map<String, SongEntity> existingMap,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<int> onProgress,
  }) async {
    final queue = Queue<SongEntity>.from(songs);
    final results = <SongEntity>[];
    var done = 0;
    const concurrency = 2;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (isCancelled()) break;
        final song = queue.removeFirst();
        TagProbeResult? meta;
        try {
          meta = await _tagProbe.probeSongDedup(
            uri: song.uri ?? '',
            isLocal: false,
            headers: headers,
            includeArtwork: false,
          );
        } catch (_) {}
        final existing = existingMap[song.id];
        results.add(_mergeWithExisting(base: song, meta: meta, existing: existing));
        done += 1;
        onProgress(done);
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
    final map = {for (final s in results) s.id: s};
    return songs.map((s) => map[s.id] ?? s).toList();
  }

  SongEntity _mergeWithExisting({
    required SongEntity base,
    required TagProbeResult? meta,
    required SongEntity? existing,
  }) {
    String pickText(String? v, String fallback) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty) return t;
      return fallback;
    }

    int? pickInt(int? v, int? fallback) {
      if (v != null && v > 0) return v;
      if (fallback != null && fallback > 0) return fallback;
      return null;
    }

    final title = pickText(meta?.title, pickText(existing?.title, base.title));
    final artist = pickText(meta?.artist, pickText(existing?.artist, base.artist));
    final album = pickText(meta?.album, pickText(existing?.album, base.album ?? ''));
    final mergedAlbum = album.isEmpty ? null : album;
    final durationMs = pickInt(meta?.durationMs, pickInt(existing?.durationMs, base.durationMs));
    final bitrate = pickInt(meta?.bitrate, pickInt(existing?.bitrate, base.bitrate));
    final sampleRate = pickInt(meta?.sampleRate, pickInt(existing?.sampleRate, base.sampleRate));
    final fileSize = pickInt(meta?.fileSize, pickInt(existing?.fileSize, base.fileSize));
    final format = pickText(meta?.format, pickText(existing?.format, base.format ?? ''));
    final mergedFormat = format.isEmpty ? null : format;
    final coverPath = pickText(existing?.localCoverPath, base.localCoverPath ?? '');
    final mergedCoverPath = coverPath.isEmpty ? null : coverPath;
    final tagsParsed = (meta != null) || (existing?.tagsParsed ?? false);
    return SongEntity(
      id: base.id,
      title: title.isEmpty ? base.title : title,
      artist: artist.isEmpty ? base.artist : artist,
      album: mergedAlbum,
      uri: base.uri,
      isLocal: false,
      headersJson: base.headersJson,
      durationMs: durationMs ?? base.durationMs,
      bitrate: bitrate ?? base.bitrate,
      sampleRate: sampleRate ?? base.sampleRate,
      fileSize: fileSize ?? base.fileSize,
      format: mergedFormat,
      sourceId: base.sourceId,
      fileModifiedMs: base.fileModifiedMs,
      localCoverPath: mergedCoverPath,
      tagsParsed: tagsParsed,
    );
  }

  bool _isAudioFile(String href) {
    final lower = href.toLowerCase();
    for (final ext in _audioExts) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  bool _shouldExclude(String path, List<String> excludeFolders) {
    final normalized = _normalizeWebDavPath(path);
    for (final ex in excludeFolders) {
      final e = _normalizeWebDavPath(ex);
      if (e.isEmpty) continue;
      if (normalized == e) return true;
      if (normalized.startsWith('$e/')) return true;
    }
    return false;
  }

  String _normalizeWebDavPath(String input) {
    var t = input.trim();
    if (t.isEmpty) return '/';
    if (!t.startsWith('/')) t = '/$t';
    t = t.replaceAll('\\', '/');
    if (t.length > 1 && t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
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

  String _normalizeWebDavHref(String href, String endpoint) {
    final raw = _repairUrlForBrokenPercentEscapes(href);
    String normalizeAbsolute(String full) {
      final parsed = Uri.tryParse(full);
      if (parsed == null) return full;
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
      return parsed.replace(pathSegments: segments).toString();
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return normalizeAbsolute(raw);
    }
    try {
      final baseUri = Uri.parse(endpoint);
      var path = raw;
      if (!path.startsWith('/')) {
        path = '/$path';
      }
      final basePath = baseUri.path;
      if (basePath.isNotEmpty && basePath != '/') {
        final normalizedBase =
            basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
        if (!path.startsWith(normalizedBase)) {
          path = '$normalizedBase$path';
        }
      }
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

      final segments = path
          .split('/')
          .where((e) => e.isNotEmpty)
          .map(decodeRepeatedly)
          .toList();
      return Uri(
        scheme: baseUri.scheme,
        userInfo: baseUri.userInfo,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        pathSegments: segments,
      ).toString();
    } catch (_) {
      return raw;
    }
  }

  String _webDavNameFromHref(String href) {
    String decodeSegment(String input) {
      try {
        return Uri.decodeComponent(input);
      } catch (_) {
        return input.replaceAll('%20', ' ');
      }
    }

    try {
      final uri = Uri.tryParse(href);
      final segments = uri?.pathSegments ?? href.split('/');
      var last = segments.lastWhere((e) => e.isNotEmpty, orElse: () => '');
      last = decodeSegment(last);
      final name = p.basenameWithoutExtension(last);
      if (name.isNotEmpty && name != '/') return name;
    } catch (_) {}

    var name = p.basenameWithoutExtension(href);
    name = decodeSegment(name);
    return name;
  }

  String _webDavAlbumFromHref(String href) {
    return '未知专辑';
  }
}
