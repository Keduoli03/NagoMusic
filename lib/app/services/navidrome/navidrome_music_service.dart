import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../state/song_state.dart';
import '../artwork_cache_helper.dart';
import '../db/dao/song_dao.dart';
import '../log/log.dart';
import 'navidrome_source_repository.dart';
import '../scan_types.dart';

class NavidromeMusicService {
  static const String _logTag = 'NavidromeMusicService';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final SongDao _songDao = SongDao();
  final NavidromeSourceRepository _repo = NavidromeSourceRepository.instance;

  Future<bool> testConnection(NavidromeSource source) async {
    try {
      final data = await _request(source, 'ping');
      return (data['status'] ?? '').toString().toLowerCase() == 'ok';
    } catch (e, s) {
      AppLog.instance.w(
        _logTag,
        '测试 Navidrome 连接失败 endpoint=${source.endpoint}',
        e,
        s,
      );
      return false;
    }
  }

  Future<ScanResult> scan({
    required NavidromeSource source,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<ScanProgress> onProgress,
  }) async {
    if (source.endpoint.trim().isEmpty || source.username.trim().isEmpty) {
      return const ScanResult(processed: 0, added: 0);
    }

    onProgress(const ScanProgress(processed: 0, added: 0, total: 0));
    final songs = <SongEntity>[];
    var processedAlbums = 0;
    var totalAlbums = 0;

    final artistsData = await _request(source, 'getArtists');
    final artists = _readList(
      artistsData['artists'],
      'index',
    ).expand((index) => _readList(index, 'artist')).toList();

    for (final artist in artists) {
      if (isCancelled()) break;
      final artistId = _readString(artist, 'id');
      if (artistId.isEmpty) continue;

      final artistData = await _request(
        source,
        'getArtist',
        query: {'id': artistId},
      );
      final albums = _readList(artistData['artist'], 'album');
      totalAlbums += albums.length;

      for (final album in albums) {
        if (isCancelled()) break;
        final albumId = _readString(album, 'id');
        if (albumId.isEmpty) continue;

        final albumData = await _request(
          source,
          'getAlbum',
          query: {'id': albumId},
        );
        final albumInfo = _asMap(albumData['album']);
        final albumSongs = _readList(albumInfo, 'song');

        // Cache the album cover once via Subsonic getCoverArt and share it with
        // every track in the album, so the song list shows covers without having
        // to play each track. Album-level keeps it to one fetch per album.
        final coverArtId = _firstNonEmpty([
          _readString(albumInfo, 'coverArt'),
          _readString(album, 'coverArt'),
          albumId,
        ]);
        String? coverPath;
        if (!isCancelled() && coverArtId.isNotEmpty) {
          coverPath = await _fetchAndCacheCover(source, coverArtId);
        }

        for (final rawSong in albumSongs) {
          final song = _songFromJson(source, albumInfo, rawSong);
          if (song == null) continue;
          songs.add(
            (coverPath != null && coverPath.isNotEmpty)
                ? song.copyWith(localCoverPath: coverPath)
                : song,
          );
        }
        processedAlbums += 1;
        onProgress(
          ScanProgress(
            processed: processedAlbums,
            added: 0,
            total: totalAlbums,
          ),
        );
      }
    }

    if (isCancelled()) {
      return ScanResult(processed: processedAlbums, added: 0);
    }

    final existingIds = await _songDao.fetchIdsBySource(source.id);
    final added = songs.where((song) => !existingIds.contains(song.id)).length;
    await _songDao.deleteBySource(source.id);
    await _songDao.upsertSongs(songs);

    onProgress(
      ScanProgress(
        processed: processedAlbums,
        added: added,
        total: totalAlbums,
      ),
    );
    return ScanResult(processed: processedAlbums, added: added);
  }

  Future<Map<String, dynamic>> _request(
    NavidromeSource source,
    String method, {
    Map<String, String> query = const {},
  }) async {
    final uri = _repo.apiUri(source, method, query: query);
    final response = await _dio.getUri<Map<String, dynamic>>(uri);
    final root = response.data?['subsonic-response'];
    if (root is! Map) {
      throw StateError('Invalid Subsonic response');
    }
    final data = root.cast<String, dynamic>();
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (status == 'failed') {
      final error = _asMap(data['error']);
      final message = _readString(error, 'message');
      throw StateError(message.isEmpty ? 'Subsonic request failed' : message);
    }
    return data;
  }

  /// Downloads an album cover via Subsonic `getCoverArt` and caches it locally,
  /// returning the cached file path (or null on failure). Skips the download
  /// when the same cover is already cached (e.g. on re-scan).
  Future<String?> _fetchAndCacheCover(
    NavidromeSource source,
    String coverArtId,
  ) async {
    final key = '${source.id}:cover:$coverArtId';
    try {
      final existing = await ArtworkCacheHelper.cachedPathIfExists(key: key);
      if (existing != null) return existing;
      final uri = _repo.apiUri(
        source,
        'getCoverArt',
        query: {'id': coverArtId, 'size': '600'},
      );
      final response = await _dio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return await ArtworkCacheHelper.cacheCompressedArtwork(
        bytes: Uint8List.fromList(data),
        key: key,
      );
    } catch (_) {
      return null;
    }
  }

  SongEntity? _songFromJson(
    NavidromeSource source,
    Map<String, dynamic> albumInfo,
    Map<String, dynamic> raw,
  ) {
    final songId = _readString(raw, 'id');
    if (songId.isEmpty) return null;

    final title = _firstNonEmpty([
      _readString(raw, 'title'),
      _readString(raw, 'name'),
      _fileNameFromPath(_readString(raw, 'path')),
      _fileNameFromPath(_readString(raw, 'fileName')),
    ]);
    final artist = _firstNonEmpty([
      _readString(raw, 'artist'),
      _readString(raw, 'artistName'),
    ]);
    final album = _readString(raw, 'album').isNotEmpty
        ? _readString(raw, 'album')
        : _firstNonEmpty([
            _readString(albumInfo, 'name'),
            _readString(albumInfo, 'title'),
          ]);
    final durationSeconds = _readInt(raw, 'duration');
    final bitrateKbps = _readInt(raw, 'bitRate');
    final uri = _repo.apiUri(source, 'stream', query: {'id': songId});

    return SongEntity(
      id: '${source.id}:$songId',
      title: title.isEmpty ? '未知标题' : title,
      artist: artist.isEmpty ? source.name : artist,
      album: album.isEmpty ? null : album,
      uri: uri.toString(),
      isLocal: false,
      durationMs: durationSeconds == null ? null : durationSeconds * 1000,
      // Subsonic reports bitRate in kbps; SongEntity stores bits per second.
      bitrate: bitrateKbps == null ? null : bitrateKbps * 1000,
      sampleRate: _readInt(raw, 'samplingRate') ?? _readInt(raw, 'sampleRate'),
      fileSize: _readInt(raw, 'size'),
      format: _readString(raw, 'suffix').isNotEmpty
          ? _readString(raw, 'suffix')
          : _readString(raw, 'contentType'),
      sourceId: source.id,
      tagsParsed: true,
      // Subsonic API surfaces both — Navidrome uses `track` (int) and
      // `discNumber` (int) on the child element. When absent the fallback
      // sort key still works, so no coalescing needed here.
      trackNumber: _readInt(raw, 'track'),
      discNumber: _readInt(raw, 'discNumber'),
    );
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _fileNameFromPath(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    try {
      text = Uri.decodeFull(text);
    } catch (_) {}
    text = text.replaceAll('\\', '/');
    final slash = text.lastIndexOf('/');
    if (slash >= 0 && slash < text.length - 1) {
      text = text.substring(slash + 1);
    }
    final dot = text.lastIndexOf('.');
    if (dot > 0) {
      text = text.substring(0, dot);
    }
    return text.trim();
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  List<Map<String, dynamic>> _readList(Object? parent, String key) {
    final map = _asMap(parent);
    final raw = map[key];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (raw is Map) {
      return [raw.cast<String, dynamic>()];
    }
    return const [];
  }

  String _readString(Map<String, dynamic> map, String key) {
    return (map[key] ?? '').toString();
  }

  int? _readInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
