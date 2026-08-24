import '../../app/services/playlists_service.dart';

/// 歌单列表页的增删改与拖拽重排逻辑，从 [PlaylistsPage] 里抽出来方便单测。
///
/// 不持有 BuildContext：确认对话框 / toast 都由调用方处理，这里只管数据。
class PlaylistsActionsController {
  final PlaylistsService _service;

  PlaylistsActionsController({PlaylistsService? service})
    : _service = service ?? PlaylistsService.instance;

  Future<PlaylistEntity> createPlaylist(String name) =>
      _service.createPlaylist(name);

  Future<void> renamePlaylist(String id, String name) =>
      _service.renamePlaylist(id, name);

  Future<void> deletePlaylist(String id) => _service.deletePlaylist(id);

  Future<void> pinToTop(String id) => _service.movePlaylistToTop(id);

  Future<void> addSongs(String playlistId, List<String> songIds) =>
      _service.addSongs(playlistId, songIds);

  /// 拖拽重排的纯计算：保持"我喜欢"歌单永远置顶、不可参与排序或被拖走。
  /// 抽成静态纯函数，不用起数据库就能覆盖边界情况。
  ///
  /// 返回 null 表示这次拖拽不合法（越界，或试图拖动"我喜欢"），调用方应放弃这次操作。
  static List<PlaylistEntity>? reorderList({
    required List<PlaylistEntity> current,
    required int oldIndex,
    required int newIndex,
  }) {
    if (oldIndex < 0 || oldIndex >= current.length) return null;
    if (newIndex < 0 || newIndex > current.length) return null;
    var adjustedNewIndex = newIndex;
    if (oldIndex < adjustedNewIndex) adjustedNewIndex -= 1;
    final list = current.toList();
    final item = list[oldIndex];
    if (item.isFavorite) return null;
    list.removeAt(oldIndex);
    list.insert(adjustedNewIndex, item);
    final favIndex = list.indexWhere((p) => p.isFavorite);
    if (favIndex > 0) {
      final fav = list.removeAt(favIndex);
      list.insert(0, fav);
    }
    return list;
  }

  /// 把非收藏歌单的当前顺序落库；"我喜欢"不参与，由 service 端固定置顶。
  Future<void> reorderPlaylists(List<PlaylistEntity> orderedList) {
    return _service.reorderPlaylists(
      orderedList.where((p) => !p.isFavorite).map((p) => p.id).toList(),
    );
  }
}
