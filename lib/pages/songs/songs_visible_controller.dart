import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart';

import '../../app/services/db/dao/song_dao.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/cache_version_store.dart';
import '../../app/utils/natural_sort.dart';
import '../../app/utils/page_cache_store.dart';
import '../../app/utils/uri_utils.dart';

class SongsVisibleResult {
  final List<SongEntity> allVisible;
  final List<SongEntity> displayVisible;

  const SongsVisibleResult({
    required this.allVisible,
    required this.displayVisible,
  });
}

class SongsVisibleController {
  static const String cacheScopeVisible = 'songs_visible';

  final PageCacheStore _cacheStore;

  SongsVisibleController({PageCacheStore? cacheStore})
    : _cacheStore = cacheStore ?? PageCacheStore.instance;

  SongsVisibleResult seedVisibleSongsFast({
    required List<SongEntity> songs,
    required String sourceFilter,
    required int currentMaxCount,
  }) {
    final filtered = _filterSongs(songs, sourceFilter);
    final maxCount = currentMaxCount > filtered.length
        ? filtered.length
        : currentMaxCount;
    return SongsVisibleResult(
      allVisible: filtered,
      displayVisible: filtered.take(maxCount).toList(),
    );
  }

  Future<SongsVisibleResult> buildVisibleSongs({
    required List<SongEntity> songs,
    required String sourceFilter,
    required String sortKey,
    required bool ascending,
    required int currentMaxCount,
    Map<String, int> playCounts = const {},
  }) async {
    // Play-count order depends on live stats, not the song-library version, so
    // bypass the cache for it to always reflect the latest counts.
    final useCache = sortKey != 'playCount';
    final cacheKey = _cacheKey(
      sourceFilter: sourceFilter,
      sortKey: sortKey,
      ascending: ascending,
    );
    final cached = useCache
        ? _cacheStore.get<List<SongEntity>>(cacheScopeVisible, cacheKey)
        : null;
    final visible =
        cached ??
        await _buildVisibleSongsAsync(
          songs: songs,
          sourceFilter: sourceFilter,
          sortKey: sortKey,
          ascending: ascending,
          playCounts: playCounts,
        );
    if (useCache && cached == null) {
      _cacheStore.set(cacheScopeVisible, cacheKey, visible);
    }
    final maxCount = currentMaxCount > visible.length
        ? visible.length
        : currentMaxCount;
    return SongsVisibleResult(
      allVisible: visible,
      displayVisible: visible.take(maxCount).toList(),
    );
  }

  String _cacheKey({
    required String sourceFilter,
    required String sortKey,
    required bool ascending,
  }) {
    final songVersion = CacheVersionStore.instance.getVersion(
      SongDao.cacheVersionScope,
    );
    return 'songv:$songVersion|$sourceFilter|$sortKey|${ascending ? 1 : 0}';
  }

  static List<SongEntity> _filterSongs(
    List<SongEntity> songs,
    String sourceFilter,
  ) {
    if (sourceFilter == 'local') {
      return songs.where((song) => song.sourceId == 'local').toList();
    }
    if (sourceFilter == 'webdav') {
      return songs.where((song) => song.sourceId != 'local').toList();
    }
    if (sourceFilter.startsWith('webdav:')) {
      final id = sourceFilter.substring('webdav:'.length);
      return songs.where((song) => song.sourceId == id).toList();
    }
    return List<SongEntity>.from(songs);
  }
}

Future<List<SongEntity>> _buildVisibleSongsAsync({
  required List<SongEntity> songs,
  required String sourceFilter,
  required String sortKey,
  required bool ascending,
  Map<String, int> playCounts = const {},
}) async {
  final payload = <String, dynamic>{
    'songs': songs.map((e) => e.toMap()).toList(),
    'sourceFilter': sourceFilter,
    'sortKey': sortKey,
    'ascending': ascending,
    'playCounts': playCounts,
  };
  final result = await compute(_buildVisibleSongsIsolate, payload);
  return result
      .map((e) => SongEntity.fromMap((e as Map).cast<String, dynamic>()))
      .toList();
}

List<Map<String, dynamic>> _buildVisibleSongsIsolate(
  Map<String, dynamic> args,
) {
  final sourceFilter = (args['sourceFilter'] as String?) ?? 'all';
  final sortKey = (args['sortKey'] as String?) ?? 'title';
  final ascending = (args['ascending'] as bool?) ?? true;
  final playCounts = ((args['playCounts'] as Map?) ?? const {}).map(
    (key, value) => MapEntry(key.toString(), (value as num).toInt()),
  );
  final rawSongs = (args['songs'] as List).cast<Map>();
  final songs = rawSongs
      .map((e) => SongEntity.fromMap(e.cast<String, dynamic>()))
      .toList();

  List<SongEntity> list;
  if (sourceFilter == 'local') {
    list = songs.where((song) => song.sourceId == 'local').toList();
  } else if (sourceFilter == 'webdav') {
    list = songs.where((song) => song.sourceId != 'local').toList();
  } else if (sourceFilter.startsWith('webdav:')) {
    final id = sourceFilter.substring('webdav:'.length);
    list = songs.where((song) => song.sourceId == id).toList();
  } else {
    list = List<SongEntity>.from(songs);
  }

  final pinyinCache = <String, String>{};
  String sortKeyStr(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '';
    final cached = pinyinCache[trimmed];
    if (cached != null) return cached;
    final p = PinyinHelper.getPinyin(
      trimmed,
      separator: '',
      format: PinyinFormat.WITHOUT_TONE,
    );
    final key = (p.isNotEmpty ? p : trimmed).toLowerCase();
    pinyinCache[trimmed] = key;
    return key;
  }

  bool isUnknownTitle(SongEntity s) =>
      s.title.trim().isEmpty || s.title == '未知标题';
  bool isUnknownArtist(SongEntity s) =>
      s.artist.trim().isEmpty || s.artist == '未知艺术家';
  bool isUnknownAlbum(SongEntity s) {
    final a = (s.album ?? '').trim();
    return a.isEmpty || a == '未知专辑';
  }

  final fileNameCache = <String, String>{};
  String fileNameOf(SongEntity s) {
    final uri = s.uri;
    if (uri == null || uri.trim().isEmpty) return '';
    final cached = fileNameCache[uri];
    if (cached != null) return cached;
    final name = UriUtils.extractFileName(uri);
    fileNameCache[uri] = name;
    return name;
  }

  int compare(SongEntity a, SongEntity b) {
    int result;
    switch (sortKey) {
      case 'artist':
        result = sortKeyStr(
          isUnknownArtist(a) ? '' : a.artist,
        ).compareTo(sortKeyStr(isUnknownArtist(b) ? '' : b.artist));
        break;
      case 'album':
        result = sortKeyStr(
          isUnknownAlbum(a) ? '' : (a.album ?? ''),
        ).compareTo(sortKeyStr(isUnknownAlbum(b) ? '' : (b.album ?? '')));
        break;
      case 'albumTrack':
        // Album-then-disc-then-track ordering so a full album plays in the
        // sequence the artist laid out. Songs missing a track/disc number
        // (older library rows before v10, or singles) sink to the bottom of
        // their album by title so the overall list still degrades gracefully.
        final albumA = sortKeyStr(isUnknownAlbum(a) ? '' : (a.album ?? ''));
        final albumB = sortKeyStr(isUnknownAlbum(b) ? '' : (b.album ?? ''));
        result = albumA.compareTo(albumB);
        if (result == 0) {
          // Missing disc / track sort AFTER numbered ones inside the album.
          final discA = a.discNumber ?? 1 << 30;
          final discB = b.discNumber ?? 1 << 30;
          result = discA.compareTo(discB);
        }
        if (result == 0) {
          final trackA = a.trackNumber ?? 1 << 30;
          final trackB = b.trackNumber ?? 1 << 30;
          result = trackA.compareTo(trackB);
        }
        if (result == 0) {
          result = sortKeyStr(
            isUnknownTitle(a) ? '' : a.title,
          ).compareTo(sortKeyStr(isUnknownTitle(b) ? '' : b.title));
        }
        break;
      case 'duration':
        result = (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
        break;
      case 'fileName':
        result = naturalCompare(fileNameOf(a), fileNameOf(b));
        break;
      case 'playCount':
        result = (playCounts[a.id] ?? 0).compareTo(playCounts[b.id] ?? 0);
        break;
      case 'title':
      default:
        result = sortKeyStr(
          isUnknownTitle(a) ? '' : a.title,
        ).compareTo(sortKeyStr(isUnknownTitle(b) ? '' : b.title));
    }
    return ascending ? result : -result;
  }

  list.sort(compare);

  if (sortKey == 'artist') {
    final unknown = list.where(isUnknownArtist).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownArtist);
      list.insertAll(0, unknown);
    }
  } else if (sortKey == 'album' || sortKey == 'albumTrack') {
    final unknown = list.where(isUnknownAlbum).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownAlbum);
      list.insertAll(0, unknown);
    }
  } else if (sortKey == 'title') {
    final unknown = list.where(isUnknownTitle).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownTitle);
      list.insertAll(0, unknown);
    }
  }

  return list.map((e) => e.toMap()).toList();
}
