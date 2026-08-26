import 'dart:convert';

import 'package:media_cache/media_cache.dart';

import '../state/song_state.dart';
import 'artwork_cache_helper.dart';
import 'db/dao/song_dao.dart';
import 'lyrics/lyrics_repository.dart';
import 'player_service.dart';
import 'playlists_service.dart';

/// 删除一整个音源（WebDAV / Navidrome / 本地）时，把这个音源名下的歌**连带**
/// 清理干净：从数据库删除本身之外，还要处理四件容易漏掉的事。
///
/// 之前各个"删除音源"页面只调了 `SongDao.deleteBySource`，单纯删数据库行，
/// 留下了四个各自独立的问题：
///
/// 1. 正在播的/播放队列里如果正好有这个音源的歌，删除后播放不会中断，下次
///    冷启动恢复播放会话时还会尝试播一首数据库里已经不存在的"幽灵歌曲"。
/// 2. `playlist_songs` 表没有外键约束，删歌单不会跟着联动，留下永远清不掉的
///    悬空引用（用户在歌单里也看不到、点不到，没有入口能手动清）。
/// 3. 歌词/封面缓存文件、远程音频字节缓存全都留在磁盘上变成孤儿文件。
/// 4. 上面这些经年累月删音源攒下来的历史脏数据，也顺手一起清掉。
class SourceDeletionService {
  SourceDeletionService._();

  static final SourceDeletionService instance = SourceDeletionService._();

  final SongDao _songDao = SongDao();
  final PlaylistsService _playlists = PlaylistsService.instance;
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final AudioCacheService _audioCache = AudioCacheService.instance;

  /// 删除 [sourceId] 名下的全部歌曲，并处理上面列的四件事。
  ///
  /// 调用方仍需自己删音源配置本身（`WebDavSourceRepository.removeById` 之类）——
  /// 这里只管"这个音源名下的歌怎么善后"。
  Future<void> deleteSongsForSource(String sourceId) async {
    final songs = await _songDao.fetchAll(sourceId: sourceId);
    if (songs.isEmpty) return;
    final ids = songs.map((s) => s.id).toList(growable: false);

    // 先把还在播的这些歌从播放队列里摘掉（数据库这时候还没删，队列里的引用
    // 仍然合法）。已有的 removeSongsById 会处理"正好删到当前播放项"的收尾
    // （切下一首/停播），这里不用再写一遍。
    await PlayerService.instance.removeSongsById(ids);

    await _songDao.deleteByIds(ids);

    // 顺带把历史上已经积累的悬空引用也一起扫掉，不只是这一批。
    await _playlists.pruneDanglingSongReferences();

    for (final song in songs) {
      await _cleanupCaches(song);
    }
  }

  Future<void> _cleanupCaches(SongEntity song) async {
    await _lyricsRepo.removeCachedLrc(song.id);

    final coverPath = (song.localCoverPath ?? '').trim();
    if (coverPath.isNotEmpty) {
      await ArtworkCacheHelper.removeCachedArtworkByPath(coverPath);
    }
    await ArtworkCacheHelper.removeCachedArtwork(key: song.id);

    final uri = (song.uri ?? '').trim();
    if (song.isLocal || uri.isEmpty || !uri.startsWith('http')) return;
    final headers = _headersFromSong(song);
    await _audioCache.removeCachedFiles(
      uri: uri,
      headers: headers.isEmpty ? null : headers,
    );
    await TagProbeService.instance.removeRemoteProbeCache(
      uri: uri,
      headers: headers.isEmpty ? null : headers,
    );
  }

  Map<String, String> _headersFromSong(SongEntity song) {
    final raw = (song.headersJson ?? '').trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return const {};
  }
}
