import 'dart:async';

import '../../state/song_state.dart';
import '../playlists_service.dart';
import 'bili_api.dart';
import 'bili_models.dart';
import 'bili_music_service.dart';

/// 同步进度回调用的快照。
class BiliSyncProgress {
  final int processed;
  final int total;
  final String label;

  const BiliSyncProgress({
    required this.processed,
    required this.total,
    required this.label,
  });
}

/// 把 B 站收藏夹同步成本地歌单。
///
/// 对齐简音的 `BiliPlaylistSyncManager`：歌单按收藏夹名字建，重复同步走
/// 「按名字找回同一个歌单再增量更新」，而不是每次新建一个。
class BiliPlaylistSync {
  static final BiliPlaylistSync instance = BiliPlaylistSync._();

  BiliPlaylistSync._();

  final BiliApi _api = BiliApi.instance;
  final BiliMusicService _music = BiliMusicService.instance;
  final PlaylistsService _playlists = PlaylistsService.instance;

  /// 同步出来的歌单统一加这个前缀，避免和用户自建歌单撞名。
  static const String playlistPrefix = 'B站 · ';

  Future<List<BiliFavFolder>> folders() => _api.favFolders();

  /// 同步一个收藏夹，返回写入的曲目数。
  ///
  /// [onProgress] 会在每个视频展开完成后回调一次 —— 多 P 视频要额外请求 view，
  /// 一个几百条的收藏夹会跑挺久，UI 必须能显示进度。
  Future<int> syncFolder(
    BiliFavFolder folder, {
    void Function(BiliSyncProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final videos = await _api.favResources(folder.id);
    final songs = <SongEntity>[];
    for (var i = 0; i < videos.length; i++) {
      if (isCancelled?.call() ?? false) break;
      final video = videos[i];
      onProgress?.call(
        BiliSyncProgress(
          processed: i,
          total: videos.length,
          label: video.title,
        ),
      );
      try {
        final expanded = await _music.songsFromFavVideo(video);
        for (final song in expanded) {
          songs.add(await _music.cacheCover(song, video.cover));
        }
      } catch (_) {
        // 单个视频失败（分区限制、已删除）跳过，不能让整次同步挂掉。
        continue;
      }
    }
    onProgress?.call(
      BiliSyncProgress(
        processed: videos.length,
        total: videos.length,
        label: '写入歌单',
      ),
    );

    await _music.persist(songs);
    await _writePlaylist('$playlistPrefix${folder.title}', songs);
    return songs.length;
  }

  /// 建歌单或复用同名歌单，然后把曲目差量写进去。
  Future<void> _writePlaylist(String name, List<SongEntity> songs) async {
    final all = await _playlists.loadAll();
    PlaylistEntity? target;
    for (final playlist in all) {
      if (!playlist.isFavorite && playlist.name == name) {
        target = playlist;
        break;
      }
    }
    target ??= await _playlists.createPlaylist(name);

    final wanted = songs.map((song) => song.id).toList();
    final wantedSet = wanted.toSet();
    final existing = target.songIds.toSet();

    // 收藏夹里被取消收藏的，本地也跟着移除；否则同步就只增不减了。
    final stale = existing
        .where((id) => id.startsWith('${BiliMusicService.sourceId}::'))
        .where((id) => !wantedSet.contains(id))
        .toList();
    if (stale.isNotEmpty) {
      await _playlists.removeSongs(target.id, stale);
    }

    final fresh = wanted.where((id) => !existing.contains(id)).toList();
    if (fresh.isNotEmpty) {
      await _playlists.addSongs(target.id, fresh);
    }
  }
}
