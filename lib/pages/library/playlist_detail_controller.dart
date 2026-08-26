import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/playlists_service.dart';
import '../../app/state/song_state.dart';

class PlaylistDetailLoadResult {
  final PlaylistEntity? playlist;
  final List<SongEntity> songs;

  const PlaylistDetailLoadResult({required this.playlist, required this.songs});
}

/// [PlaylistDetailPage] 的加载 / 移除 / 重排逻辑。
///
/// 这里的"移除"是把歌曲从这个歌单里摘除（解除 playlistId-songId 关联），
/// 歌曲本身还在曲库里 —— 跟 `songs/songs_actions_controller.dart` 里
/// `SongsActionsController.removeSongs` 那种连库带缓存一起删除歌曲的语义完全不同，
/// 所以没有复用它，而是新开一个轻量控制器。
class PlaylistDetailController {
  final PlaylistsService _service;
  final SongDao _songDao;

  PlaylistDetailController({PlaylistsService? service, SongDao? songDao})
    : _service = service ?? PlaylistsService.instance,
      _songDao = songDao ?? SongDao();

  Future<PlaylistDetailLoadResult> load(String playlistId) async {
    final all = await _service.loadAll();
    final playlist = _firstWhereOrNull(all, (p) => p.id == playlistId);
    final songs = playlist == null
        ? const <SongEntity>[]
        : await _songDao.fetchByIds(playlist.songIds);
    return PlaylistDetailLoadResult(playlist: playlist, songs: songs);
  }

  Future<void> removeSong(String playlistId, String songId) =>
      _service.removeSongs(playlistId, [songId]);

  /// 从歌单里批量移除。形状跟 `SongsActionsController.removeSongs` 一致：
  /// 调用方通过回调更新 UI（是否 mounted 也由回调自己判断）。
  ///
  /// 这里没有缓存文件要删 —— 从歌单移除并不删歌曲本身 —— 所以整件事就是一条
  /// `DELETE ... WHERE playlistId = ? AND songId IN (...)`。以前是每首歌单独发
  /// 一条，200 首就是 200 次 DB 往返加 200 次歌单缓存失效。
  Future<int> removeSongs({
    required String playlistId,
    required List<SongEntity> songsToRemove,
    required Future<void> Function(int processed, int total) onProgress,
    required Future<void> Function(SongEntity removedSong) onSongRemoved,
  }) async {
    if (songsToRemove.isEmpty) return 0;
    final total = songsToRemove.length;

    await _service.removeSongs(
      playlistId,
      songsToRemove.map((s) => s.id).toList(growable: false),
    );

    // 回调仍然逐首发：调用方用它把行从列表里摘掉、更新进度文案，改成一次性传
    // 整批会牵动它那边的一堆状态，收益却为零（DB 已经在上面一把删完了）。
    for (final song in songsToRemove) {
      await onSongRemoved(song);
    }
    await onProgress(total, total);
    return total;
  }

  Future<void> reorderSongs(String playlistId, List<String> orderedSongIds) =>
      _service.reorderSongs(playlistId, orderedSongIds);
}

T? _firstWhereOrNull<T>(List<T> list, bool Function(T) test) {
  for (final item in list) {
    if (test(item)) return item;
  }
  return null;
}
