import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services/playlists_service.dart';
import '../../app/utils/cache_version_store.dart';
import '../../app/utils/page_cache_store.dart';

class PlaylistsSortPrefs {
  final String sortMode;
  final bool ascending;

  const PlaylistsSortPrefs({required this.sortMode, required this.ascending});
}

/// 歌单列表页的排序偏好读写 + 列表加载/排序管线，镜像
/// `songs/songs_visible_controller.dart` 的分层方式：偏好存取、缓存读写、
/// 纯排序计算三件事分开，方便各自单测。
class PlaylistsSortController {
  static const String cacheScope = 'playlists_page';
  static const String prefsSortMode = 'playlists_sort_mode_v1';
  static const String prefsSortAscending = 'playlists_sort_ascending_v1';

  final PlaylistsService _service;
  final PageCacheStore _cacheStore;

  PlaylistsSortController({
    PlaylistsService? service,
    PageCacheStore? cacheStore,
  }) : _service = service ?? PlaylistsService.instance,
       _cacheStore = cacheStore ?? PageCacheStore.instance;

  Future<PlaylistsSortPrefs> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var mode = (prefs.getString(prefsSortMode) ?? 'custom').trim();
    if (mode.isEmpty) mode = 'custom';
    final ascending = prefs.getBool(prefsSortAscending) ?? true;
    return PlaylistsSortPrefs(sortMode: mode, ascending: ascending);
  }

  Future<void> savePrefs({
    required String sortMode,
    required bool ascending,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsSortMode, sortMode);
    await prefs.setBool(prefsSortAscending, ascending);
  }

  /// 按歌单库版本号缓存全量歌单列表；版本没变就直接命中缓存，省一次 DB 查询。
  Future<List<PlaylistEntity>> loadPlaylists() async {
    final cacheKey =
        'playlistsv:${CacheVersionStore.instance.getVersion(PlaylistsService.cacheVersionScope)}';
    final cached = _cacheStore.get<List<PlaylistEntity>>(cacheScope, cacheKey);
    if (cached != null) return cached;
    final playlists = await _service.loadAll();
    _cacheStore.set(cacheScope, cacheKey, playlists);
    return playlists;
  }

  /// 纯排序计算：custom 模式原样返回（拖拽顺序由调用方直接维护），其余模式
  /// 按 key 排序后把"我喜欢"重新置顶。
  static List<PlaylistEntity> sortPlaylists({
    required List<PlaylistEntity> playlists,
    required String sortMode,
    required bool ascending,
  }) {
    if (sortMode == 'custom') return playlists;

    final favorite = playlists.where((p) => p.isFavorite).toList();
    final others = playlists.where((p) => !p.isFavorite).toList();

    int compare(PlaylistEntity a, PlaylistEntity b) {
      switch (sortMode) {
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'count':
          return a.songIds.length.compareTo(b.songIds.length);
        case 'recent':
        default:
          return a.createdAtMs.compareTo(b.createdAtMs);
      }
    }

    others.sort(compare);
    if (!ascending) {
      others.replaceRange(0, others.length, others.reversed);
    }

    return [...favorite, ...others];
  }
}
