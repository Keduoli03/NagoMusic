import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/state/settings_state.dart';
import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/router/app_page_route.dart';
import '../../app/services/app_update_service.dart';
import '../../app/services/backup/backup_service.dart';
import '../../app/services/library_refresh_service.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/utils/cache_version_store.dart';
import '../../app/utils/page_cache_store.dart';
import '../../components/index.dart';
import '../../components/dialog/app_update_dialog.dart';
import '../library/albums_page.dart';
import '../library/artists_page.dart';
import '../library/folders_page.dart';
import 'home_recommender.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _DiscoveryKind { daily, recommended, heart }

/// 一张发现卡的静态配置 + 它对应的歌单，从 build 里拆出来只是为了让三张卡走同一
/// 条渲染路径，不用把 itemBuilder 写成三段 if。
class _DiscoverySpec {
  final _DiscoveryKind kind;
  final String eyebrow;
  final String title;
  final IconData? icon;
  final Color accent;
  final SongEntity? cover;
  final List<SongEntity> songs;

  const _DiscoverySpec({
    required this.kind,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.accent,
    required this.cover,
    required this.songs,
  });
}

class _HomePageState extends State<HomePage> with SignalsMixin {
  static const String _prefsHomeFilter = 'home_filter';
  static const String _cacheScope = 'home_counts';

  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final SongDao _songDao = SongDao();
  final PlayerService _player = PlayerService.instance;
  final PlaylistsService _playlistsService = PlaylistsService.instance;
  final StatsService _statsService = StatsService.instance;
  final LibraryRefreshService _libraryRefreshService =
      LibraryRefreshService.instance;
  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final NavidromeSourceRepository _navidromeRepo =
      NavidromeSourceRepository.instance;
  final PageCacheStore _cacheStore = PageCacheStore.instance;
  bool _libraryRefreshTried = false;

  late final _filter = createSignal('all');
  late final _loading = createSignal(true);
  late final _countAll = createSignal(0);
  late final _countLocal = createSignal(0);
  late final _countRemote = createSignal(0);
  late final _webDavSources = createSignal<List<WebDavSource>>([]);
  late final _webDavCounts = createSignal<Map<String, int>>({});
  late final _navidromeSources = createSignal<List<NavidromeSource>>([]);
  late final _navidromeCounts = createSignal<Map<String, int>>({});
  late final _recentSongs = createSignal<List<SongEntity>>([]);
  late final _recentAlbums = createSignal<List<_RecentAlbumItem>>([]);
  late final _recentPlaylists = createSignal<List<PlaylistEntity>>([]);
  late final _librarySongs = createSignal<List<SongEntity>>([]);
  late final _favoriteSongIds = createSignal<Set<String>>({});
  late final _activeDiscovery = createSignal<_DiscoveryKind?>(null);
  // Behaviour data driving the home recommender. Refreshed alongside the
  // library counts in _load.
  late final _playCounts = createSignal<Map<String, int>>({});
  late final _lastPlayedMs = createSignal<Map<String, int>>({});

  late final _webDavNameMap = computed<Map<String, String>>(() {
    final map = <String, String>{};
    for (final s in _webDavSources.value) {
      final name = s.name.trim().isEmpty ? 'WebDAV' : s.name.trim();
      map[s.id] = name;
    }
    for (final s in _navidromeSources.value) {
      final name = s.name.trim().isEmpty ? 'Navidrome' : s.name.trim();
      map[s.id] = name;
    }
    return map;
  });

  late final _filterTitle = computed<String>(() {
    final filter = _filter.value;
    if (filter == 'local') return '本地音乐';
    if (filter == 'webdav') return '云端（全部）';
    if (filter.startsWith('webdav:')) {
      final id = filter.substring('webdav:'.length);
      final name = _webDavNameMap.value[id];
      return '云端：${(name ?? id).trim()}';
    }
    return '全部';
  });

  late final _filterCount = computed<int>(() {
    final filter = _filter.value;
    if (filter == 'local') return _countLocal.value;
    if (filter == 'webdav') return _countRemote.value;
    if (filter.startsWith('webdav:')) {
      final id = filter.substring('webdav:'.length);
      return _webDavCounts.value[id] ?? _navidromeCounts.value[id] ?? 0;
    }
    return _countAll.value;
  });

  @override
  void initState() {
    super.initState();
    unawaited(_tryAutoPlayOnAppLaunch());
    unawaited(_tryRefreshLibraryOnLaunch());
    unawaited(_tryCheckUpdateOnLaunch());
    unawaited(BackupService.instance.maybeAutoBackupOnLaunch());
    _load();
  }

  Future<void> _tryCheckUpdateOnLaunch() async {
    await AppLaunchUpdateSettings.ensureLoaded();
    if (AppLaunchUpdateSettings.hasCheckedUpdateThisSession) return;
    AppLaunchUpdateSettings.hasCheckedUpdateThisSession = true;
    if (!AppLaunchUpdateSettings.autoCheckUpdateOnLaunch.value) return;
    // Let the app settle before reaching out / showing a dialog.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    try {
      final current = await AppUpdateService.instance.currentVersion();
      final info = await AppUpdateService.instance.checkLatest(current);
      if (!mounted || !info.hasUpdate) return;
      await showAppUpdateDialog(context, info: info, currentVersion: current);
    } catch (e) {
      debugPrint('Auto check update on launch failed: $e');
    }
  }

  Future<void> _tryAutoPlayOnAppLaunch() async {
    await AppLaunchPlaybackSettings.ensureLoaded();
    if (AppLaunchPlaybackSettings.hasHandledAutoPlayThisSession) {
      return;
    }
    AppLaunchPlaybackSettings.hasHandledAutoPlayThisSession = true;
    if (!mounted || !AppLaunchPlaybackSettings.autoPlayOnAppLaunch.value) {
      return;
    }
    var attempts = 0;
    while (_player.currentSong.value == null && attempts < 8) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      attempts += 1;
    }
    while (!_player.hasLoadedAudioSource && attempts < 16) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      attempts += 1;
    }
    if (_player.currentSong.value == null ||
        _player.isPlaying.value ||
        !_player.hasLoadedAudioSource) {
      return;
    }
    try {
      await _player.play();
    } catch (e) {
      debugPrint('App auto play on launch failed: $e');
    }
  }

  Future<void> _tryRefreshLibraryOnLaunch() async {
    if (_libraryRefreshTried) return;
    _libraryRefreshTried = true;

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final result = await _libraryRefreshService.refreshOnLaunch();
    if (!mounted || result == null) return;
    if (!result.hasChanges) return;

    await _load(includeWebDavCounts: true);
    if (!mounted) return;

    final parts = <String>[];
    if (result.localAdded > 0) {
      parts.add('本地 ${result.localAdded} 首');
    }
    if (result.cloudAdded > 0) {
      parts.add('云端 ${result.cloudAdded} 首');
    }
    final detail = parts.join('，');
    AppToast.show(context, '已自动刷新音源，新增 $detail', type: ToastType.success);
  }

  Future<void> _load({bool includeWebDavCounts = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsHomeFilter) ?? 'all';
    final cacheKey =
        'songv:${CacheVersionStore.instance.getVersion(SongDao.cacheVersionScope)}';

    final cached = _cacheStore.get<_HomeCountsCache>(_cacheScope, cacheKey);
    if (cached != null) {
      _countAll.value = cached.countAll;
      _countLocal.value = cached.countLocal;
      _countRemote.value = cached.countRemote;
      _webDavSources.value = cached.webDavSources;
      _webDavCounts.value = cached.webDavCounts;
      _navidromeSources.value = cached.navidromeSources;
      _navidromeCounts.value = cached.navidromeCounts;
      _loading.value = false;
    }

    final needsWebDavCounts = includeWebDavCounts || raw.startsWith('webdav:');
    await _refreshData(
      cacheKey: cacheKey,
      rawFilter: raw,
      includeWebDavCounts: needsWebDavCounts,
    );
  }

  Future<void> _refreshData({
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
      final entries = await Future.wait(
        sources.map(
          (s) async =>
              MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
        ),
      );
      webdavCounts = {for (final e in entries) e.key: e.value};
      final navidromeEntries = await Future.wait(
        navidromeSources.map(
          (s) async =>
              MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
        ),
      );
      navidromeCounts = {for (final e in navidromeEntries) e.key: e.value};
    } else {
      webdavCounts =
          _cacheStore
              .get<_HomeCountsCache>(_cacheScope, cacheKey)
              ?.webDavCounts ??
          const {};
      navidromeCounts =
          _cacheStore
              .get<_HomeCountsCache>(_cacheScope, cacheKey)
              ?.navidromeCounts ??
          const {};
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
    if (!mounted) return;

    _cacheStore.set(
      _cacheScope,
      cacheKey,
      _HomeCountsCache(
        countAll: counts[0],
        countLocal: counts[1],
        countRemote: counts[2],
        webDavSources: sources,
        webDavCounts: webdavCounts,
        navidromeSources: navidromeSources,
        navidromeCounts: navidromeCounts,
      ),
    );

    _filter.value = filter;
    _countAll.value = counts[0];
    _countLocal.value = counts[1];
    _countRemote.value = counts[2];
    _webDavSources.value = sources;
    _webDavCounts.value = webdavCounts;
    _navidromeSources.value = navidromeSources;
    _navidromeCounts.value = navidromeCounts;
    _recentSongs.value = recentSongs;
    _recentPlaylists.value = recentPlaylists.take(6).toList();
    _recentAlbums.value = recentAlbums;
    _librarySongs.value = librarySongs;
    _favoriteSongIds.value = favoriteSongIds;
    _playCounts.value = playCounts;
    _lastPlayedMs.value = lastPlayed;
    _loading.value = false;
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

  bool _matchesCurrentSource(SongEntity song) {
    final filter = _filter.value;
    if (filter == 'all') return true;
    if (filter == 'local') return song.isLocal;
    if (filter == 'webdav') return !song.isLocal;
    if (filter.startsWith('webdav:')) {
      return song.sourceId == filter.substring('webdav:'.length);
    }
    return true;
  }

  HomeRecommender _recommender() {
    return HomeRecommender(
      now: DateTime.now(),
      playCounts: _playCounts.value,
      lastPlayedMs: _lastPlayedMs.value,
      favoriteIds: _favoriteSongIds.value,
    );
  }

  // 下面这几个 computed 是首页卡顿的关键。
  //
  // 以前它们是普通方法，在 body 的 Watch.builder 里直接调用，于是：
  //   1. 每次重建都要把整个曲库过滤一遍 —— 三个方法各拷一份，
  //      `_recommendedSongs` 内部还会再跑一次 `heart()`（有时还有 `daily()`），
  //      一次重建最多四趟全量打分；
  //   2. 那个 Watch.builder 同时还读了 `isPlayingSignal` / `queueSignal`，
  //      所以**每次播放/暂停、每次队列变化都会重跑整套推荐**。
  //
  // 换成 computed 之后，它们只在真正的输入（曲库、筛选、播放次数、最近播放、
  // 收藏）变化时才重算；播放状态变了不会碰它们。
  late final _filteredPool = computed<List<SongEntity>>(
    () => _librarySongs.value.where(_matchesCurrentSource).toList(),
  );

  late final _dailySongs = computed<List<SongEntity>>(
    () => _recommender().daily(_filteredPool.value),
  );

  late final _heartModeSongs = computed<List<SongEntity>>(
    () => _recommender().heart(_filteredPool.value),
  );

  late final _recommendedSongs = computed<List<SongEntity>>(
    // 把已经算好的 heart / daily 结果传进去复用 —— 不传的话 recommended() 内部会
    // 把整个曲库重新打分排序一到两遍，而这两份首页本来就已经有了。
    () => _recommender().recommended(
      _filteredPool.value,
      limit: 6,
      heartRanked: _heartModeSongs.value,
      dailyRanked: _dailySongs.value,
    ),
  );

  late final _discoveryCovers = computed<List<SongEntity?>>(
    () => _distinctDiscoveryCovers([
      _dailySongs.value,
      _recommendedSongs.value,
      _heartModeSongs.value,
    ]),
  );

  List<SongEntity?> _distinctDiscoveryCovers(List<List<SongEntity>> groups) {
    final usedIds = <String>{};
    return groups
        .map((songs) {
          SongEntity? selected;
          for (final song in songs) {
            if (!usedIds.contains(song.id)) {
              selected = song;
              break;
            }
          }
          selected ??= songs.firstOrNull;
          if (selected != null) usedIds.add(selected.id);
          return selected;
        })
        .toList(growable: false);
  }

  Future<void> _playDiscoveryQueue(
    List<SongEntity> songs,
    _DiscoveryKind kind,
  ) async {
    if (songs.isEmpty) {
      AppToast.show(context, '当前音源还没有可播放的歌曲');
      return;
    }
    _activeDiscovery.value = kind;
    await _player.playQueue(songs, 0);
  }

  bool _isDiscoveryQueueActive(
    _DiscoveryKind kind,
    List<SongEntity> songs,
    List<SongEntity> playerQueue,
  ) {
    if (_activeDiscovery.value != kind) return false;
    final playableIds = songs
        .where((song) => (song.uri ?? '').trim().isNotEmpty)
        .map((song) => song.id)
        .toList(growable: false);
    if (playableIds.length != playerQueue.length || playableIds.isEmpty) {
      return false;
    }
    for (var index = 0; index < playableIds.length; index++) {
      if (playableIds[index] != playerQueue[index].id) return false;
    }
    return true;
  }

  List<_RecentAlbumItem> _buildRecentAlbums(List<SongEntity> songs) {
    final items = <_RecentAlbumItem>[];
    final seen = <String>{};
    for (final song in songs) {
      final albumName = (song.album ?? '').trim().isEmpty
          ? '未知专辑'
          : song.album!.trim();
      if (!seen.add(albumName)) continue;
      items.add(_RecentAlbumItem(name: albumName, representative: song));
      if (items.length >= 6) break;
    }
    return items;
  }

  Future<void> _refreshWebDavCounts() async {
    final sources = await _webDavRepo.loadSources();
    final navidromeSources = await _navidromeRepo.loadSources();
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
    if (!mounted) return;
    final webdavCounts = {for (final e in entries) e.key: e.value};
    final navidromeCounts = {for (final e in navidromeEntries) e.key: e.value};
    final cacheKey =
        'songv:${CacheVersionStore.instance.getVersion(SongDao.cacheVersionScope)}';
    final previous = _cacheStore.get<_HomeCountsCache>(_cacheScope, cacheKey);
    if (previous != null) {
      _cacheStore.set(
        _cacheScope,
        cacheKey,
        previous.copyWith(
          webDavSources: sources,
          webDavCounts: webdavCounts,
          navidromeSources: navidromeSources,
          navidromeCounts: navidromeCounts,
        ),
      );
    }
    _webDavSources.value = sources;
    _webDavCounts.value = webdavCounts;
    _navidromeSources.value = navidromeSources;
    _navidromeCounts.value = navidromeCounts;
  }

  Future<void> _setFilter(String next) async {
    _filter.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsHomeFilter, next);
  }

  Future<void> _showSourceSheet() async {
    await _refreshWebDavCounts();
    if (!mounted) return;
    final sources = _webDavSources.value;
    final navidromeSources = _navidromeSources.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final items = [
          const _HomeSourceItem(label: '全部', value: 'all'),
          const _HomeSourceItem(label: '本地', value: 'local'),
          const _HomeSourceItem(label: '云端（全部）', value: 'webdav'),
        ];
        final cloudIds = [
          ...sources.map((s) => s.id),
          ...navidromeSources.map((s) => s.id),
        ]..sort();
        return AppSheetPanel(
          title: '切换音源',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...items.map((item) {
                final isSelected = _filter.value == item.value;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(item.label),
                  trailing: isSelected ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    _setFilter(item.value);
                    Navigator.pop(context);
                  },
                );
              }),
              if (cloudIds.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 24),
                  title: Text('暂无云端音源'),
                  enabled: false,
                )
              else
                ...cloudIds.map((id) {
                  final value = 'webdav:$id';
                  final isSelected = _filter.value == value;
                  final name = _webDavNameMap.value[id];
                  final label = (name ?? id).trim();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text('云端：$label'),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      _setFilter(value);
                      Navigator.pop(context);
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // Top-level destinations (歌曲/专辑/艺术家/歌单) are peers of the home page:
  // replace the stack so back from them triggers the double-press-to-exit flow
  // instead of returning here.
  Future<void> _openTopLevel(Widget page) async {
    if (AppLayoutSettings.navigationStyle.value ==
        AppNavigationStyle.bottomBar) {
      await Navigator.of(context).push(buildAppPageRoute<void>((_) => page));
      return;
    }
    await Navigator.of(context).pushAndRemoveUntil(
      buildAppPageRoute<void>((_) => page),
      (route) => false,
    );
  }

  List<_HomeSourceItem> _topSourceItems() {
    final items = <_HomeSourceItem>[
      const _HomeSourceItem(label: '综合', value: 'all'),
      const _HomeSourceItem(label: '本地', value: 'local'),
    ];
    for (final source in _webDavSources.value) {
      items.add(
        _HomeSourceItem(
          label: source.name.trim().isEmpty ? 'WebDAV' : source.name.trim(),
          value: 'webdav:${source.id}',
        ),
      );
    }
    for (final source in _navidromeSources.value) {
      items.add(
        _HomeSourceItem(
          label: source.name.trim().isEmpty ? 'Navidrome' : source.name.trim(),
          value: 'webdav:${source.id}',
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        key: _scaffoldKey,
        extendBodyBehindAppBar: true,
        appBar: AppTopBar(
          titleWidget: Watch.builder(
            builder: (context) => _HomeSourceTabs(
              items: _topSourceItems(),
              selectedValue: _filter.value,
              onSelected: _setFilter,
            ),
          ),
          showBackButton: false,
          centerTitle: false,
          leading: useBottomNavigation
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
          actions: [
            IconButton(
              tooltip: '管理音源',
              icon: const Icon(Icons.tune_rounded),
              onPressed: _showSourceSheet,
            ),
            const SizedBox(width: 4),
          ],
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        drawer: useBottomNavigation
            ? null
            : SideMenu(
                onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
        bottomNavIndex: useBottomNavigation ? 0 : null,
        onBottomNavTap: useBottomNavigation
            ? (index) => navigateToPrimaryDestination(context, index)
            : null,
        body: RefreshIndicator(
          onRefresh: () => _load(includeWebDavCounts: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
            children: [
              // 每一块各自订阅自己需要的 signal。以前整个 ListView 裹在一个
              // Watch.builder 里，任何一个 signal 变化都要重建全部内容 ——
              // 包括六个 ArtworkWidget，而封面重建意味着重新解码。
              Watch.builder(
                builder: (context) => _HomeSourceSummary(
                  title: _filterTitle.value,
                  count: _filterCount.value,
                  loading: _loading.value,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: _DiscoveryCard.height,
                child: Watch.builder(
                  builder: (context) {
                    final covers = _discoveryCovers.value;
                    final specs = <_DiscoverySpec>[
                      _DiscoverySpec(
                        kind: _DiscoveryKind.daily,
                        eyebrow: '每日推荐',
                        title: '今日限定好歌推荐',
                        icon: Icons.calendar_month_rounded,
                        accent: const Color(0xFFEF4444),
                        cover: covers[0],
                        songs: _dailySongs.value,
                      ),
                      _DiscoverySpec(
                        kind: _DiscoveryKind.recommended,
                        eyebrow: '雷达歌单',
                        title: '反复聆听你爱的歌',
                        icon: null,
                        accent: const Color(0xFF38A3A5),
                        cover: covers[1],
                        songs: _recommendedSongs.value,
                      ),
                      _DiscoverySpec(
                        kind: _DiscoveryKind.heart,
                        eyebrow: '心动模式',
                        title: '红心歌曲和相似推荐',
                        icon: Icons.favorite_rounded,
                        accent: const Color(0xFF8B7CF6),
                        cover: covers[2],
                        songs: _heartModeSongs.value,
                      ),
                    ];
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: specs.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final spec = specs[index];
                        // 播放态单独订阅：播放/暂停只重建这三张卡的外框，
                        // 不会波及封面之外的东西，更不会重跑推荐。
                        return Watch.builder(
                          builder: (context) => _DiscoveryCard(
                            eyebrow: spec.eyebrow,
                            title: spec.title,
                            icon: spec.icon,
                            song: spec.cover,
                            accent: spec.accent,
                            active: _isDiscoveryQueueActive(
                              spec.kind,
                              spec.songs,
                              _player.queueSignal.value,
                            ),
                            playing: _player.isPlayingSignal.value,
                            onTap: () =>
                                _playDiscoveryQueue(spec.songs, spec.kind),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              Watch.builder(
                builder: (context) {
                  final recommendedSongs = _recommendedSongs.value;
                  return _HomeRecommendationSection(
                    songs: recommendedSongs,
                    onPlayAll: () => _playDiscoveryQueue(
                      recommendedSongs,
                      _DiscoveryKind.recommended,
                    ),
                    onTapSong: (song) async {
                      final index = recommendedSongs.indexWhere(
                        (item) => item.id == song.id,
                      );
                      await _player.playQueue(
                        recommendedSongs,
                        index < 0 ? 0 : index,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 28),
              // 不依赖任何 signal —— 放在 Watch 外面就不会跟着重建。
              _HomeQuickLibrary(
                onArtists: () => _openTopLevel(const ArtistsPage()),
                onAlbums: () => _openTopLevel(const AlbumsPage()),
                onFolders: () => _openTopLevel(const FoldersPage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSourceTabs extends StatelessWidget {
  final List<_HomeSourceItem> items;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  const _HomeSourceTabs({
    required this.items,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = selectedValue == item.value;
          // 胶囊 Tab（对齐模板的 PillTabBar）：选中态是主题色淡底 + 主题色字，
          // 不再用 Material 那条蓝下划线。
          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!selected) Haptics.selection();
                onSelected(item.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? scheme.primary : c.muted,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeSourceSummary extends StatelessWidget {
  final String title;
  final int count;
  final bool loading;

  const _HomeSourceSummary({
    required this.title,
    required this.count,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          loading ? '正在更新' : '$count 首歌曲',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  static const double width = 120;
  static const double _coverSize = 120;
  static const double _footerHeight = 38;
  static const double height = _coverSize + _footerHeight;

  final String eyebrow;
  final String title;
  final IconData? icon;
  final SongEntity? song;
  final Color accent;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  const _DiscoveryCard({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.song,
    required this.accent,
    required this.active,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = song;
    final footerColor = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      const Color(0xFF211B1B),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Column(
              children: [
                SizedBox(
                  width: _coverSize,
                  height: _coverSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (currentSong != null)
                        // 这里刻意**不用** preferOriginal。卡片只有 120 逻辑像素，
                        // 3x 屏也就需要 360px，而磁盘缓存里的封面是 1024px，绰绰有余。
                        // preferOriginal 会绕开缓存、在 UI isolate 上同步解析音频标签
                        // 取出 1~3MB 的内嵌大图 —— 切换筛选时三张卡连着做三次，
                        // 这是首页最贵的一笔开销，而且在这个尺寸上肉眼看不出差别。
                        //
                        // keepPreviousUntilLoaded：换歌时先留着旧封面，别先闪成空白。
                        ArtworkWidget(
                          song: currentSong,
                          size: _coverSize,
                          borderRadius: 0,
                          keepPreviousUntilLoaded: true,
                        )
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.95),
                                accent.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x59000000),
                              Color(0x00000000),
                              Color(0x26000000),
                            ],
                            stops: [0, 0.48, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        right: 7,
                        child: Row(
                          children: [
                            if (icon == Icons.calendar_month_rounded)
                              const _DiscoveryCalendarBadge()
                            else if (icon != null)
                              Icon(icon, color: Colors.white, size: 17),
                            if (icon != null) const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                eyebrow,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x8A000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 6,
                        child: active
                            ? PlayingBars(
                                color: Colors.white,
                                animating: playing,
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                                shadows: [
                                  Shadow(
                                    color: Color(0x8F000000),
                                    blurRadius: 5,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: width,
                  height: _footerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  color: footerColor,
                  alignment: Alignment.center,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoveryCalendarBadge extends StatelessWidget {
  const _DiscoveryCalendarBadge();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 1.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Text(
                    '${DateTime.now().day}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(left: 4, top: 0, child: _CalendarBinding()),
          const Positioned(right: 4, top: 0, child: _CalendarBinding()),
        ],
      ),
    );
  }
}

class _CalendarBinding extends StatelessWidget {
  const _CalendarBinding();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
      ),
      child: const SizedBox(width: 1.5, height: 4),
    );
  }
}

class _HomeRecommendationSection extends StatefulWidget {
  final List<SongEntity> songs;
  final VoidCallback onPlayAll;
  final ValueChanged<SongEntity> onTapSong;

  const _HomeRecommendationSection({
    required this.songs,
    required this.onPlayAll,
    required this.onTapSong,
  });

  @override
  State<_HomeRecommendationSection> createState() =>
      _HomeRecommendationSectionState();
}

class _HomeRecommendationSectionState
    extends State<_HomeRecommendationSection> {
  final PageController _pageController = PageController();

  @override
  void didUpdateWidget(covariant _HomeRecommendationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.songs.map((song) => song.id).join('|');
    final newIds = widget.songs.map((song) => song.id).join('|');
    if (oldIds != newIds && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '根据你喜欢的歌曲推荐',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            SoftIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: '播放全部',
              onTap: widget.onPlayAll,
              size: 34,
              iconSize: 21,
              radius: AppRadii.card,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.songs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.panel),
            ),
            child: Text(
              '收藏几首喜欢的歌后，这里会出现更贴合你的推荐',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 198,
            child: PageView.builder(
              controller: _pageController,
              itemCount: (widget.songs.length + 2) ~/ 3,
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * 3;
                final end = min(start + 3, widget.songs.length);
                return Column(
                  children: widget.songs
                      .sublist(start, end)
                      .map(
                        (song) => _RecommendationSongTile(
                          song: song,
                          onTap: () => widget.onTapSong(song),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RecommendationSongTile extends StatelessWidget {
  final SongEntity song;
  final VoidCallback onTap;

  const _RecommendationSongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Row(
          children: [
            ArtworkWidget(song: song, size: 52, borderRadius: AppRadii.chip),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            // 原来这里是一个孤零零的黑色 ▶ 图标，看不出是控件也不像卡片语言。
            SoftIconButton(
              icon: Icons.play_arrow_rounded,
              onTap: onTap,
              size: 28,
              iconSize: 17,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _HomeQuickLibrary extends StatelessWidget {
  final VoidCallback onArtists;
  final VoidCallback onAlbums;
  final VoidCallback onFolders;

  const _HomeQuickLibrary({
    required this.onArtists,
    required this.onAlbums,
    required this.onFolders,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 三个瓦片各带一个强调色，但颜色只落在图标底上 —— 瓦片本身是和卡片同族的
    // 白底方角，不再是三块撞色渐变。
    final buttons = <_QuickLibraryData>[
      _QuickLibraryData(
        label: '艺术家',
        icon: Icons.person_outline_rounded,
        accent: scheme.primary,
        onTap: onArtists,
      ),
      _QuickLibraryData(
        label: '专辑',
        icon: Icons.album_outlined,
        accent: scheme.tertiary,
        onTap: onAlbums,
      ),
      _QuickLibraryData(
        label: '文件夹',
        icon: Icons.folder_outlined,
        accent: scheme.secondary,
        onTap: onFolders,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _QuickLibraryButton(data: buttons[i])),
        ],
      ],
    );
  }
}

class _QuickLibraryData {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _QuickLibraryData({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

class _QuickLibraryButton extends StatelessWidget {
  final _QuickLibraryData data;

  const _QuickLibraryButton({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = BorderRadius.circular(AppRadii.card);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          Haptics.tap();
          data.onTap();
        },
        child: Ink(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: radius,
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Icon(data.icon, size: 17, color: data.accent),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCountsCache {
  final int countAll;
  final int countLocal;
  final int countRemote;
  final List<WebDavSource> webDavSources;
  final Map<String, int> webDavCounts;
  final List<NavidromeSource> navidromeSources;
  final Map<String, int> navidromeCounts;

  const _HomeCountsCache({
    required this.countAll,
    required this.countLocal,
    required this.countRemote,
    required this.webDavSources,
    required this.webDavCounts,
    this.navidromeSources = const [],
    this.navidromeCounts = const {},
  });

  _HomeCountsCache copyWith({
    int? countAll,
    int? countLocal,
    int? countRemote,
    List<WebDavSource>? webDavSources,
    Map<String, int>? webDavCounts,
    List<NavidromeSource>? navidromeSources,
    Map<String, int>? navidromeCounts,
  }) {
    return _HomeCountsCache(
      countAll: countAll ?? this.countAll,
      countLocal: countLocal ?? this.countLocal,
      countRemote: countRemote ?? this.countRemote,
      webDavSources: webDavSources ?? this.webDavSources,
      webDavCounts: webDavCounts ?? this.webDavCounts,
      navidromeSources: navidromeSources ?? this.navidromeSources,
      navidromeCounts: navidromeCounts ?? this.navidromeCounts,
    );
  }
}

class _RecentAlbumItem {
  final String name;
  final SongEntity representative;

  const _RecentAlbumItem({required this.name, required this.representative});
}

class _HomeSourceItem {
  final String label;
  final String value;

  const _HomeSourceItem({required this.label, required this.value});
}
