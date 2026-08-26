import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/cache_version_store.dart';
import '../../app/utils/page_cache_store.dart';
import 'home_models.dart';

/// 一次 webdav/navidrome 计数刷新的结果，[HomeDataController.refreshWebDavCounts]
/// 返回它，调用方决定要不要落地缓存、要不要更新 signal。
class HomeWebDavCountsRefresh {
  final List<WebDavSource> webDavSources;
  final Map<String, int> webDavCounts;
  final List<NavidromeSource> navidromeSources;
  final Map<String, int> navidromeCounts;

  const HomeWebDavCountsRefresh({
    required this.webDavSources,
    required this.webDavCounts,
    required this.navidromeSources,
    required this.navidromeCounts,
  });
}

/// [HomeDataController.refreshAll] 的完整结果 —— 首页一次加载需要的全部数据，
/// 不含 filter 之外的任何 UI 状态。
class HomeLoadResult {
  final String filter;
  final int countAll;
  final int countLocal;
  final int countRemote;
  final List<WebDavSource> webDavSources;
  final Map<String, int> webDavCounts;
  final List<NavidromeSource> navidromeSources;
  final Map<String, int> navidromeCounts;
  final List<SongEntity> recentSongs;
  final List<PlaylistEntity> recentPlaylists;
  final List<RecentAlbumItem> recentAlbums;
  final List<SongEntity> librarySongs;
  final Set<String> favoriteSongIds;
  final Map<String, int> playCounts;
  final Map<String, int> lastPlayedMs;

  const HomeLoadResult({
    required this.filter,
    required this.countAll,
    required this.countLocal,
    required this.countRemote,
    required this.webDavSources,
    required this.webDavCounts,
    required this.navidromeSources,
    required this.navidromeCounts,
    required this.recentSongs,
    required this.recentPlaylists,
    required this.recentAlbums,
    required this.librarySongs,
    required this.favoriteSongIds,
    required this.playCounts,
    required this.lastPlayedMs,
  });
}

/// 首页的数据加载与计数缓存，从 [HomePage] 里抽出来方便单测。
///
/// 不持有 BuildContext / signal：加载结果通过纯数据结构返回，是否落地缓存、
/// 何时更新 UI 由调用方（State）在 `mounted` 检查之后决定 —— 镜像原来
/// `_HomePageState._refreshData` 里"算完了发现已经 unmounted 就连缓存都不写"
/// 的顺序，不能简化成"controller 内部自己写缓存"。
class HomeDataController {
  static const String cacheScope = 'home_counts';
  static const String prefsHomeFilterKey = 'home_filter';

  final SongDao _songDao;
  final PlaylistsService _playlistsService;
  final StatsService _statsService;
  final WebDavSourceRepository _webDavRepo;
  final NavidromeSourceRepository _navidromeRepo;
  final PageCacheStore _cacheStore;

  HomeDataController({
    SongDao? songDao,
    PlaylistsService? playlistsService,
    StatsService? statsService,
    WebDavSourceRepository? webDavRepository,
    NavidromeSourceRepository? navidromeRepository,
    PageCacheStore? cacheStore,
  }) : _songDao = songDao ?? SongDao(),
       _playlistsService = playlistsService ?? PlaylistsService.instance,
       _statsService = statsService ?? StatsService.instance,
       _webDavRepo = webDavRepository ?? WebDavSourceRepository.instance,
       _navidromeRepo =
           navidromeRepository ?? NavidromeSourceRepository.instance,
       _cacheStore = cacheStore ?? PageCacheStore.instance;

  /// 按歌曲库版本号算出来的缓存 key —— 曲库没变就复用上一份计数。
  String currentCacheKey() =>
      'songv:${CacheVersionStore.instance.getVersion(SongDao.cacheVersionScope)}';

  Future<String> loadFilterPref() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsHomeFilterKey) ?? 'all';
  }

  HomeCountsCache? peekCachedCounts(String cacheKey) =>
      _cacheStore.get<HomeCountsCache>(cacheScope, cacheKey);

  void cacheCounts(String cacheKey, HomeLoadResult result) {
    _cacheStore.set(
      cacheScope,
      cacheKey,
      HomeCountsCache(
        countAll: result.countAll,
        countLocal: result.countLocal,
        countRemote: result.countRemote,
        webDavSources: result.webDavSources,
        webDavCounts: result.webDavCounts,
        navidromeSources: result.navidromeSources,
        navidromeCounts: result.navidromeCounts,
      ),
    );
  }

  Future<HomeLoadResult> refreshAll({
    required String cacheKey,
    required String rawFilter,
    required bool includeWebDavCounts,
  }) async {
    final countsFuture = Future.wait<int>([
      _songDao.countAll(),
      _songDao.countLocal(),
      _songDao.countRemote(),
    ]);
    final sourcesFuture = _webDavRepo.loadSources();
    final navidromeSourcesFuture = _navidromeRepo.loadSources();
    final recentSongsFuture = _loadRecentSongs();
    final playlistsFuture = _playlistsService.loadAll();
    final librarySongsFuture = _songDao.fetchAllCached();
    // Parallel with the DB fetches — recommender inputs.
    final playCountsFuture = _statsService.fetchPlayCounts();
    final lastPlayedFuture = _statsService.fetchLastPlayedTimestamps();

    final counts = await countsFuture;
    final sources = await sourcesFuture;
    final navidromeSources = await navidromeSourcesFuture;
    final recentSongs = await recentSongsFuture;
    final playlists = await playlistsFuture;
    final librarySongs = await librarySongsFuture;
    final playCounts = await playCountsFuture;
    final lastPlayed = await lastPlayedFuture;
    final recentPlaylists = playlists.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final favorite = playlists.where((playlist) => playlist.isFavorite);
    final favoriteSongIds = favorite.isEmpty
        ? const <String>{}
        : favorite.first.songIds.toSet();
    final recentAlbums = _buildRecentAlbums(recentSongs);

    Map<String, int> webdavCounts;
    Map<String, int> navidromeCounts;
    if (includeWebDavCounts) {
      final refresh = await _fetchWebDavCounts(sources, navidromeSources);
      webdavCounts = refresh.webDavCounts;
      navidromeCounts = refresh.navidromeCounts;
    } else {
      final previous = peekCachedCounts(cacheKey);
      webdavCounts = previous?.webDavCounts ?? const {};
      navidromeCounts = previous?.navidromeCounts ?? const {};
    }

    var filter = rawFilter;
    if (filter.startsWith('webdav:')) {
      final id = filter.substring('webdav:'.length);
      final exists =
          sources.any((s) => s.id == id) ||
          navidromeSources.any((s) => s.id == id);
      if (!exists) {
        filter = 'webdav';
      }
    } else if (filter != 'local' && filter != 'webdav' && filter != 'all') {
      filter = 'all';
    }

    return HomeLoadResult(
      filter: filter,
      countAll: counts[0],
      countLocal: counts[1],
      countRemote: counts[2],
      webDavSources: sources,
      webDavCounts: webdavCounts,
      navidromeSources: navidromeSources,
      navidromeCounts: navidromeCounts,
      recentSongs: recentSongs,
      recentPlaylists: recentPlaylists.take(6).toList(),
      recentAlbums: recentAlbums,
      librarySongs: librarySongs,
      favoriteSongIds: favoriteSongIds,
      playCounts: playCounts,
      lastPlayedMs: lastPlayed,
    );
  }

  Future<HomeWebDavCountsRefresh> refreshWebDavCounts() async {
    final sources = await _webDavRepo.loadSources();
    final navidromeSources = await _navidromeRepo.loadSources();
    return _fetchWebDavCounts(sources, navidromeSources);
  }

  void cacheWebDavCounts(HomeWebDavCountsRefresh refresh) {
    final cacheKey = currentCacheKey();
    final previous = peekCachedCounts(cacheKey);
    if (previous == null) return;
    _cacheStore.set(
      cacheScope,
      cacheKey,
      previous.copyWith(
        webDavSources: refresh.webDavSources,
        webDavCounts: refresh.webDavCounts,
        navidromeSources: refresh.navidromeSources,
        navidromeCounts: refresh.navidromeCounts,
      ),
    );
  }

  Future<HomeWebDavCountsRefresh> _fetchWebDavCounts(
    List<WebDavSource> sources,
    List<NavidromeSource> navidromeSources,
  ) async {
    final entries = await Future.wait(
      sources.map(
        (s) async =>
            MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
      ),
    );
    final navidromeEntries = await Future.wait(
      navidromeSources.map(
        (s) async =>
            MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
      ),
    );
    return HomeWebDavCountsRefresh(
      webDavSources: sources,
      webDavCounts: {for (final e in entries) e.key: e.value},
      navidromeSources: navidromeSources,
      navidromeCounts: {for (final e in navidromeEntries) e.key: e.value},
    );
  }

  Future<List<SongEntity>> _loadRecentSongs() async {
    final recentStats = await _statsService.fetchRecentSongs(limit: 12);
    final ids = recentStats
        .map((e) => e.songId)
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return const [];
    final songs = await _songDao.fetchByIds(ids);
    return songs.take(6).toList();
  }

  List<RecentAlbumItem> _buildRecentAlbums(List<SongEntity> songs) {
    final items = <RecentAlbumItem>[];
    final seen = <String>{};
    for (final song in songs) {
      final albumName = (song.album ?? '').trim().isEmpty
          ? '未知专辑'
          : song.album!.trim();
      if (!seen.add(albumName)) continue;
      items.add(RecentAlbumItem(name: albumName, representative: song));
      if (items.length >= 6) break;
    }
    return items;
  }
}
