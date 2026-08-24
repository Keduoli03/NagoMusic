import 'package:shared_preferences/shared_preferences.dart';

/// B 站模块自己的一点本地偏好。
class BiliPrefs {
  const BiliPrefs._();

  static const String _visibleFolders = 'bili_visible_fav_folders_v1';

  /// 允许显示在 B站 主页的收藏夹 id。
  ///
  /// **空集合表示「全部显示」**，而不是「一个都不显示」—— 没配置过的用户不该
  /// 打开就看到一片空白。
  static Future<Set<int>> visibleFolderIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_visibleFolders);
    if (raw == null) return const {};
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> setVisibleFolderIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_visibleFolders);
      return;
    }
    await prefs.setStringList(
      _visibleFolders,
      ids.map((e) => e.toString()).toList(),
    );
  }

  /// 按偏好过滤收藏夹列表。
  static List<T> filterFolders<T>(
    List<T> folders,
    Set<int> visible,
    int Function(T) idOf,
  ) {
    if (visible.isEmpty) return folders;
    final kept = folders.where((f) => visible.contains(idOf(f))).toList();
    // 配置过但一个都没匹配上（收藏夹被删了），退回全部显示而不是空白。
    return kept.isEmpty ? folders : kept;
  }
}
