import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../state/song_state.dart';
import '../db/dao/song_dao.dart';
import 'navidrome_source_repository.dart';

class NavidromeScanProgress {
  final int processed;
  final int added;
  final int total;

  const NavidromeScanProgress({
    required this.processed,
    required this.added,
    required this.total,
  });
}

class NavidromeScanResult {
  final int processed;
  final int added;

  const NavidromeScanResult({required this.processed, required this.added});
}

class NavidromeMusicService {
  final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 12)),
  );
  final SongDao _songDao = SongDao();
  final NavidromeSourceRepository _repo = NavidromeSourceRepository.instance;

  Future<bool> testConnection(NavidromeSource source) async {
    try {
      final data = await _request(source, 'ping');
      return (data['status'] ?? '').toString().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<NavidromeScanResult> scan({
    required NavidromeSource source,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<NavidromeScanProgress> onProgress,
  }) async {
    if (source.endpoint.trim().isEmpty || source.username.trim().isEmpty) {
      return const NavidromeScanResult(processed: 0, added: 0);
    }

    onProgress(const NavidromeScanProgress(processed: 0, added: 0, total: 0));
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
        for (final rawSong in albumSongs) {
          final song = _songFromJson(source, albumInfo, rawSong);
          if (song != null) songs.add(song);
        }
        processedAlbums += 1;
        onProgress(
          NavidromeScanProgress(
            processed: processedAlbums,
            added: 0,
            total: totalAlbums,
          ),
        );
      }
    }

    if (isCancelled()) {
      return NavidromeScanResult(processed: processedAlbums, added: 0);
    }

    final existingIds = await _songDao.fetchIdsBySource(source.id);
    final added = songs.where((song) => !existingIds.contains(song.id)).length;
    await _songDao.deleteBySource(source.id);
    await _songDao.upsertSongs(songs);

    onProgress(
      NavidromeScanProgress(
        processed: processedAlbums,
        added: added,
        total: totalAlbums,
      ),
    );
    return NavidromeScanResult(processed: processedAlbums, added: added);
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

  SongEntity? _songFromJson(
    NavidromeSource source,
    Map<String, dynamic> albumInfo,
    Map<String, dynamic> raw,
  ) {
    final songId = _readString(raw, 'id');
    if (songId.isEmpty) return null;

    final title = _readString(raw, 'title');
    final artist = _readString(raw, 'artist');
    final album = _readString(raw, 'album').isNotEmpty
        ? _readString(raw, 'album')
        : _readString(albumInfo, 'name');
    final durationSeconds = _readInt(raw, 'duration');
    final uri = _repo.apiUri(source, 'stream', query: {'id': songId});

    return SongEntity(
      id: '${source.id}:$songId',
      title: title.isEmpty ? '未知标题' : title,
      artist: artist.isEmpty ? source.name : artist,
      album: album.isEmpty ? null : album,
      uri: uri.toString(),
      isLocal: false,
      durationMs: durationSeconds == null ? null : durationSeconds * 1000,
      bitrate: _readInt(raw, 'bitRate'),
      fileSize: _readInt(raw, 'size'),
      format: _readString(raw, 'suffix').isNotEmpty
          ? _readString(raw, 'suffix')
          : _readString(raw, 'contentType'),
      sourceId: source.id,
      tagsParsed: true,
    );
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
