import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_cache/media_cache.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../../state/song_state.dart';
import '../../utils/webdav_song_id.dart';
import '../artwork_cache_helper.dart';
import '../log/log.dart';
import '../db/dao/song_dao.dart';
import 'webdav_endpoint_resolver.dart';
import 'webdav_source_repository.dart';
import 'webdav_url.dart';
import '../scan_types.dart';

/// Thrown when a WebDAV scan cannot reach/authenticate against the server, so
/// callers can distinguish a genuine connection failure from an empty folder.
class WebDavScanException implements Exception {
  final String message;
  final Object? cause;

  const WebDavScanException(this.message, [this.cause]);

  @override
  String toString() => 'WebDavScanException: $message';
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
  final WebDavEndpointResolver _endpointResolver =
      WebDavEndpointResolver.instance;
  final AppLog _logs = AppLog.instance;

  static const _audioExts = {
    '.mp3',
    '.flac',
    '.wav',
    '.m4a',
    '.ogg',
    '.aac',
    '.opus',
  };

  // Network timeouts so a dead/slow server can never hang the UI/scan forever.
  static const int _connectTimeoutMs = 15000;
  static const int _sendTimeoutMs = 15000;
  static const int _receiveTimeoutMs = 30000;

  // Scheme probing tries up to two candidates back to back, so it uses a much
  // tighter budget than a real request — otherwise "auto" on an http-only host
  // makes the user wait out a full 15s https connect before anything happens.
  static const int _probeTimeoutMs = 6000;

  /// Redirect hops chased while probing. Three is plenty for the real chains
  /// (http → https, and bare-domain → www), and stops a misconfigured server
  /// from spinning us.
  static const int _maxRedirectHops = 3;

  // How many PROPFINDs are in flight at once while walking the tree. Directory
  // listing is pure latency (one round trip each, tiny payloads), so walking
  // depth-first one folder at a time meant a 200-folder library cost 200 serial
  // round trips. 6 is a deliberate ceiling: OpenList and most reverse proxies
  // start returning 429/503 somewhere above 8-10 concurrent PROPFINDs.
  static const int _dirConcurrency = 6;

  webdav.Client _newClient(
    String endpoint,
    Map<String, String> headers, {
    int? timeoutMs,
  }) {
    final client = webdav.newClient(
      normalizeWebDavEndpoint(endpoint),
      user: '',
      password: '',
      debug: kDebugMode,
    );
    client.setHeaders(headers);
    client.setConnectTimeout(timeoutMs ?? _connectTimeoutMs);
    client.setSendTimeout(timeoutMs ?? _sendTimeoutMs);
    client.setReceiveTimeout(timeoutMs ?? _receiveTimeoutMs);
    return client;
  }

  /// Finds which concrete URL for [rawEndpoint] actually answers, and returns
  /// it fully-qualified.
  ///
  /// This is what lets the user type a bare `ol.example.com/dav`: with no
  /// scheme, [webDavEndpointCandidates] expands to https-then-http and each is
  /// probed in turn. With a scheme present (typed, or picked in the protocol
  /// row) there is exactly one candidate, so a failure is reported as a
  /// failure instead of silently downgrading the connection.
  ///
  /// Each candidate that fails outright gets a redirect chase before being
  /// written off — see [_discoverRedirect].
  ///
  /// Returns null when nothing answers.
  Future<String?> resolveEndpoint(
    WebDavSource source, {
    String? rawEndpoint,
    String? forcedScheme,
  }) async {
    final candidates = webDavEndpointCandidates(
      rawEndpoint ?? source.endpoint,
      forcedScheme: forcedScheme,
    );
    final tried = <String>{};
    for (final candidate in candidates) {
      if (!tried.add(candidate)) continue;
      if (await _testEndpoint(source, candidate, timeoutMs: _probeTimeoutMs)) {
        return candidate;
      }
      final redirected = await _discoverRedirect(source, candidate);
      if (redirected == null || !tried.add(redirected)) continue;
      if (await _testEndpoint(source, redirected, timeoutMs: _probeTimeoutMs)) {
        return redirected;
      }
    }
    return null;
  }

  /// Asks [endpoint] where it would rather send us, following up to
  /// [_maxRedirectHops] hops, and returns that address.
  ///
  /// Needed because nothing in the stack follows a redirect for us:
  /// webdav_client sets `followRedirects = false`, and Dart's HttpClient only
  /// auto-follows on GET/HEAD regardless. So against the very common reverse
  /// proxy that answers plain http with `301 → https://…`, every PROPFIND
  /// fails outright — which is why picking HTTP for such a host used to look
  /// like a wrong password rather than a wrong scheme.
  ///
  /// The probe is a GET rather than a PROPFIND because the scheme-upgrade
  /// redirect is issued by the proxy before it ever looks at the method, and a
  /// GET is the request every server is guaranteed to answer.
  Future<String?> _discoverRedirect(
    WebDavSource source,
    String endpoint,
  ) async {
    var current = normalizeWebDavEndpoint(endpoint);
    if (current.isEmpty) return null;
    final origin = Uri.tryParse(current);
    if (origin == null) return null;

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: _probeTimeoutMs),
        sendTimeout: const Duration(milliseconds: _probeTimeoutMs),
        receiveTimeout: const Duration(milliseconds: _probeTimeoutMs),
        followRedirects: false,
        validateStatus: (_) => true,
        headers: _repo.buildHeaders(source),
      ),
    );

    try {
      for (var hop = 0; hop < _maxRedirectHops; hop++) {
        final response = await dio.getUri(Uri.parse(current));
        final status = response.statusCode ?? 0;
        if (status < 300 || status >= 400) return null;

        final location = response.headers.value('location');
        if (location == null || location.trim().isEmpty) return null;

        final next = Uri.parse(current).resolve(location.trim());
        if (next.scheme != 'http' && next.scheme != 'https') return null;

        current = buildWebDavEndpoint(
          scheme: next.scheme,
          host: next.host,
          port: next.hasPort ? next.port : null,
          path: next.path,
        );
        // Landing back where we started means a redirect loop, not a fix.
        if (current == normalizeWebDavEndpoint(endpoint)) return null;
        if (next.scheme != origin.scheme || next.host != origin.host) {
          return current;
        }
      }
    } catch (_) {
      return null;
    } finally {
      dio.close(force: true);
    }
    return null;
  }

  Future<bool> testConnection(WebDavSource source) async {
    return _testEndpoint(source, source.endpoint);
  }

  /// Tests every configured address (primary + alternates) independently,
  /// so the settings UI can show which ones currently work.
  Future<Map<String, bool>> testConnections(WebDavSource source) async {
    final endpoints = source.allEndpoints;
    final result = <String, bool>{};
    for (final endpoint in endpoints) {
      result[endpoint] = await _testEndpoint(source, endpoint);
    }
    return result;
  }

  Future<bool> _testEndpoint(
    WebDavSource source,
    String endpoint, {
    int? timeoutMs,
  }) async {
    final trimmed = normalizeWebDavEndpoint(endpoint);
    if (trimmed.isEmpty) return false;
    final headers = _repo.buildHeaders(source);
    try {
      final client = _newClient(trimmed, headers, timeoutMs: timeoutMs);
      final searchPath = _normalizeWebDavPath(
        source.path.trim().isEmpty ? '/' : source.path,
      );
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
    final endpoint = normalizeWebDavEndpoint(source.endpoint);
    if (endpoint.isEmpty) return const [];
    final headers = _repo.buildHeaders(source);
    final entries = await _listEntriesStrict(
      client: _newClient(endpoint, headers),
      path: _normalizeWebDavPath(path),
    );

    final dirs =
        entries
            .where((e) => (e.isDir ?? false) == true)
            .map((e) {
              final rawPath = (e.path ?? '').toString();
              final normalized = _normalizeWebDavPath(rawPath);
              final name = p.basename(normalized);
              return WebDavDirectory(
                name: name.isEmpty ? normalized : name,
                path: normalized,
              );
            })
            .where((d) => d.path.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return dirs;
  }

  Future<ScanResult> scan({
    required WebDavSource source,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<ScanProgress> onProgress,
  }) async {
    final resolvedEndpoint = await _endpointResolver.resolveActiveEndpoint(
      source,
      forceRefresh: true,
    );
    final endpoint = normalizeWebDavEndpoint(
      resolvedEndpoint ?? source.endpoint,
    );
    if (endpoint.isEmpty) {
      return const ScanResult(processed: 0, added: 0);
    }
    await _logs.ensureLoaded();

    final pathsToScan = source.includeFolders.isNotEmpty
        ? source.includeFolders
        : [(source.path.trim().isEmpty ? '/' : source.path.trim())];
    final exclude = source.excludeFolders
        .map((e) => _normalizeWebDavPath(e))
        .toList();
    final headers = _repo.buildHeaders(source);
    final seenFiles = <String>{};

    // One client for the whole scan. The previous code built a fresh
    // webdav/Dio client per directory, which threw away the connection pool —
    // every folder paid a new TCP + TLS handshake, and on an https host that
    // dominated the scan time.
    final client = _newClient(endpoint, headers);

    // Probe the first target path strictly so connection/auth/timeout failures
    // surface as an exception instead of being silently swallowed by the
    // lenient per-directory listing (which would report "added 0" as success).
    try {
      await _listEntriesStrict(
        client: client,
        path: _normalizeWebDavPath(pathsToScan.first),
      );
    } catch (e) {
      throw WebDavScanException('无法连接到 WebDAV 服务器，请检查地址、账号或网络', e);
    }

    var discovered = 0;
    var scannedDirs = 0;
    onProgress(const ScanProgress(processed: 0, added: 0, total: 0));

    final collected = <SongEntity>[];
    await _scanTree(
      client: client,
      endpoint: endpoint,
      roots: pathsToScan,
      excludeFolders: exclude,
      isCancelled: isCancelled,
      onDirectoryDone: () {
        scannedDirs += 1;
        // Deep libraries can go a long time between audio files. Without this
        // the dialog sits at 0 and looks hung, which is exactly what a slow
        // scan used to look like.
        onProgress(
          ScanProgress(processed: discovered, added: 0, total: scannedDirs),
        );
      },
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
            // Path-based, not the raw href — stays stable across the
            // source's alternate addresses (see webdav_song_id.dart).
            id: buildWebdavSongId(sourceId: source.id, hrefOrUri: href),
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
        onProgress(
          ScanProgress(processed: discovered, added: 0, total: scannedDirs),
        );
      },
    );

    if (isCancelled()) {
      return ScanResult(processed: discovered, added: 0);
    }

    final existingList = await _songDao.fetchAll(sourceId: source.id);
    final existingMap = {for (final s in existingList) s.id: s};
    final existingIds = existingMap.keys.toSet();

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
              .map(
                (s) => _mergeWithExisting(
                  base: s,
                  meta: null,
                  existing: existingMap[s.id],
                ),
              )
              .toList();

    if (isCancelled()) {
      return ScanResult(processed: discovered, added: 0);
    }

    final added = enriched
        .where((song) => !existingIds.contains(song.id))
        .length;
    await _songDao.deleteBySource(source.id);
    await _songDao.upsertSongs(enriched);
    onProgress(
      ScanProgress(processed: discovered, added: added, total: discovered),
    );
    return ScanResult(processed: discovered, added: added);
  }

  /// Walks the tree under [roots] breadth-first, listing up to
  /// [_dirConcurrency] directories at a time.
  ///
  /// Breadth-first rather than the old depth-first recursion because it's what
  /// makes the concurrency usable: every directory at the current depth is
  /// known up front, so a whole level can go out in parallel batches instead of
  /// one folder blocking on its own children.
  Future<void> _scanTree({
    required webdav.Client client,
    required String endpoint,
    required List<String> roots,
    required List<String> excludeFolders,
    required ValueGetter<bool> isCancelled,
    required VoidCallback onDirectoryDone,
    required ValueChanged<String> onFile,
  }) async {
    final visited = <String>{};
    var frontier = <String>[];
    for (final root in roots) {
      final normalized = _normalizeWebDavPath(root);
      if (_shouldExclude(normalized, excludeFolders)) continue;
      if (visited.add(normalized)) frontier.add(normalized);
    }

    while (frontier.isNotEmpty) {
      if (isCancelled()) return;
      final next = <String>[];

      for (var i = 0; i < frontier.length; i += _dirConcurrency) {
        if (isCancelled()) return;
        final batch = frontier.skip(i).take(_dirConcurrency).toList();
        final listings = await Future.wait(
          batch.map((path) => _listEntries(client: client, path: path)),
        );

        for (var b = 0; b < batch.length; b++) {
          final parent = batch[b];
          onDirectoryDone();
          for (final entry in listings[b]) {
            if ((entry.isDir ?? false) == true) {
              final childPath = _normalizeWebDavPath(entry.path ?? '');
              if (childPath == parent || childPath.isEmpty) continue;
              if (_shouldExclude(childPath, excludeFolders)) continue;
              if (!visited.add(childPath)) continue;
              next.add(childPath);
              continue;
            }
            final href = _normalizeWebDavHref(entry.path ?? '', endpoint);
            if (!_isAudioFile(href)) continue;
            onFile(href);
          }
        }
      }

      frontier = next;
    }
  }

  Future<List<webdav.File>> _listEntries({
    required webdav.Client client,
    required String path,
  }) async {
    try {
      return await _listEntriesStrict(client: client, path: path);
    } catch (_) {
      return const [];
    }
  }

  Future<List<webdav.File>> _listEntriesStrict({
    required webdav.Client client,
    required String path,
  }) async {
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
    // Tag probing does ranged GETs, so it's heavier per request than a
    // PROPFIND — kept well below _dirConcurrency on purpose.
    const concurrency = 4;

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (isCancelled()) break;
        final song = queue.removeFirst();
        TagProbeResult? meta;
        String? coverPath;
        try {
          meta = await _tagProbe.probeSongDedup(
            uri: song.uri ?? '',
            isLocal: false,
            headers: headers,
            includeArtwork: true,
          );
          final artwork = meta?.artwork;
          final existingCoverPath = (existingMap[song.id]?.localCoverPath ?? '')
              .trim();
          if (existingCoverPath.isNotEmpty) {
            coverPath = existingCoverPath;
          } else if (artwork != null && artwork.isNotEmpty) {
            coverPath = await ArtworkCacheHelper.cacheCompressedArtwork(
              bytes: artwork,
              key: song.id,
            );
          }
          if (meta == null) {
            _logScanIssue(
              source: song.sourceId ?? 'unknown',
              uri: song.uri ?? song.id,
              reason: 'probe returned null',
              song: song,
              existing: existingMap[song.id],
              meta: meta,
              coverPath: coverPath,
            );
          } else if ((meta.title ?? '').trim().isEmpty &&
              (meta.artist ?? '').trim().isEmpty &&
              (meta.album ?? '').trim().isEmpty &&
              (meta.durationMs ?? 0) <= 0 &&
              (coverPath ?? '').trim().isEmpty) {
            _logScanIssue(
              source: song.sourceId ?? 'unknown',
              uri: song.uri ?? song.id,
              reason: 'probe returned empty metadata',
              song: song,
              existing: existingMap[song.id],
              meta: meta,
              coverPath: coverPath,
            );
          }
        } catch (e) {
          _logScanIssue(
            source: song.sourceId ?? 'unknown',
            uri: song.uri ?? song.id,
            reason: 'probe threw $e',
            song: song,
            existing: existingMap[song.id],
            meta: meta,
            coverPath: coverPath,
          );
        }
        final existing = existingMap[song.id];
        results.add(
          _mergeWithExisting(
            base: song,
            meta: meta,
            existing: existing,
            resolvedCoverPath: coverPath,
          ),
        );
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
    String? resolvedCoverPath,
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
    final artist = pickText(
      meta?.artist,
      pickText(existing?.artist, base.artist),
    );
    final album = pickText(
      meta?.album,
      pickText(existing?.album, base.album ?? ''),
    );
    final mergedAlbum = album.isEmpty ? null : album;
    final durationMs = pickInt(
      meta?.durationMs,
      pickInt(existing?.durationMs, base.durationMs),
    );
    final bitrate = pickInt(
      meta?.bitrate,
      pickInt(existing?.bitrate, base.bitrate),
    );
    final sampleRate = pickInt(
      meta?.sampleRate,
      pickInt(existing?.sampleRate, base.sampleRate),
    );
    final fileSize = pickInt(
      meta?.fileSize,
      pickInt(existing?.fileSize, base.fileSize),
    );
    final format = pickText(
      meta?.format,
      pickText(existing?.format, base.format ?? ''),
    );
    final mergedFormat = format.isEmpty ? null : format;
    final coverPath = pickText(
      resolvedCoverPath,
      pickText(existing?.localCoverPath, base.localCoverPath ?? ''),
    );
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
      localAssetId: base.localAssetId,
      tagsParsed: tagsParsed,
    );
  }

  void _logScanIssue({
    required String source,
    required String uri,
    required String reason,
    required SongEntity song,
    required SongEntity? existing,
    required TagProbeResult? meta,
    required String? coverPath,
  }) {
    final shortUri = uri.length > 180 ? '${uri.substring(0, 180)}...' : uri;
    String host = '-';
    try {
      final parsed = Uri.tryParse(uri);
      host = (parsed?.host ?? '').trim().isEmpty ? '-' : parsed!.host;
    } catch (_) {}
    final ext = p.extension(uri).toLowerCase();
    final hasTitle = (meta?.title ?? '').trim().isNotEmpty ? 1 : 0;
    final hasArtist = (meta?.artist ?? '').trim().isNotEmpty ? 1 : 0;
    final hasAlbum = (meta?.album ?? '').trim().isNotEmpty ? 1 : 0;
    final hasDuration = (meta?.durationMs ?? 0) > 0 ? 1 : 0;
    final hasArtwork = (meta?.artwork?.isNotEmpty ?? false) ? 1 : 0;
    final hasCoverPath = ((coverPath ?? '').trim().isNotEmpty) ? 1 : 0;
    final hadExistingCover =
        ((existing?.localCoverPath ?? '').trim().isNotEmpty) ? 1 : 0;
    _logs.d(
      'WebDavScan',
      '[$source] $reason | host=$host ext=$ext parsed=${song.tagsParsed ? 1 : 0} title=$hasTitle artist=$hasArtist album=$hasAlbum duration=$hasDuration artwork=$hasArtwork cachedCover=$hasCoverPath existingCover=$hadExistingCover :: $shortUri',
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

    bool isWs(int cu) => cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;
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
        final normalizedBase = basePath.endsWith('/')
            ? basePath.substring(0, basePath.length - 1)
            : basePath;
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
