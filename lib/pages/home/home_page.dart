import 'dart:async';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:signals/signals.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/state/settings_state.dart';
import '../../app/router/app_page_route.dart';
import '../../app/services/app_update_service.dart';
import '../../app/services/backup/backup_service.dart';
import '../../app/services/library_refresh_service.dart';
import '../../app/services/log/log.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/state/song_state.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../components/index.dart';
import '../../components/dialog/app_update_dialog.dart';
import '../library/albums_page.dart';
import '../library/artists_page.dart';
import '../library/folders_page.dart';
import 'home_actions_controller.dart';
import 'home_data_controller.dart';
import 'home_models.dart';
import 'home_recommender.dart';
import 'widgets/discovery_card.dart';
import 'widgets/home_quick_library.dart';
import 'widgets/home_recommendation_section.dart';
import 'widgets/home_source_tabs.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SignalsMixin {
  static const String _logTag = 'HomePage';

  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final PlayerService _player = PlayerService.instance;
  final LibraryRefreshService _libraryRefreshService =
      LibraryRefreshService.instance;
  final HomeDataController _dataController = HomeDataController();
  final HomeActionsController _actionsController = HomeActionsController();
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
  late final _recentAlbums = createSignal<List<RecentAlbumItem>>([]);
  late final _recentPlaylists = createSignal<List<PlaylistEntity>>([]);
  late final _librarySongs = createSignal<List<SongEntity>>([]);
  late final _favoriteSongIds = createSignal<Set<String>>({});
  late final _activeDiscovery = createSignal<DiscoveryKind?>(null);
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '启动时自动检查更新失败', e, s);
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '启动时自动播放失败', e, s);
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
    final raw = await _dataController.loadFilterPref();
    final cacheKey = _dataController.currentCacheKey();

    final cached = _dataController.peekCachedCounts(cacheKey);
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
    final result = await _dataController.refreshAll(
      cacheKey: cacheKey,
      rawFilter: rawFilter,
      includeWebDavCounts: includeWebDavCounts,
    );
    if (!mounted) return;

    _dataController.cacheCounts(cacheKey, result);

    _filter.value = result.filter;
    _countAll.value = result.countAll;
    _countLocal.value = result.countLocal;
    _countRemote.value = result.countRemote;
    _webDavSources.value = result.webDavSources;
    _webDavCounts.value = result.webDavCounts;
    _navidromeSources.value = result.navidromeSources;
    _navidromeCounts.value = result.navidromeCounts;
    _recentSongs.value = result.recentSongs;
    _recentPlaylists.value = result.recentPlaylists;
    _recentAlbums.value = result.recentAlbums;
    _librarySongs.value = result.librarySongs;
    _favoriteSongIds.value = result.favoriteSongIds;
    _playCounts.value = result.playCounts;
    _lastPlayedMs.value = result.lastPlayedMs;
    _loading.value = false;
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
    DiscoveryKind kind,
  ) async {
    await _actionsController.playDiscoveryQueue(
      songs: songs,
      onEmpty: () => AppToast.show(context, '当前音源还没有可播放的歌曲'),
      onStart: () => _activeDiscovery.value = kind,
    );
  }

  bool _isDiscoveryQueueActive(
    DiscoveryKind kind,
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

  Future<void> _refreshWebDavCounts() async {
    final refresh = await _dataController.refreshWebDavCounts();
    if (!mounted) return;
    _dataController.cacheWebDavCounts(refresh);
    _webDavSources.value = refresh.webDavSources;
    _webDavCounts.value = refresh.webDavCounts;
    _navidromeSources.value = refresh.navidromeSources;
    _navidromeCounts.value = refresh.navidromeCounts;
  }

  Future<void> _setFilter(String next) async {
    _filter.value = next;
    await _actionsController.setFilter(next);
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
          const HomeSourceItem(label: '全部', value: 'all'),
          const HomeSourceItem(label: '本地', value: 'local'),
          const HomeSourceItem(label: '云端（全部）', value: 'webdav'),
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
                  trailing: isSelected ? const Icon(AppIcons.check) : null,
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
                    trailing: isSelected ? const Icon(AppIcons.check) : null,
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

  List<HomeSourceItem> _topSourceItems() {
    final items = <HomeSourceItem>[
      const HomeSourceItem(label: '综合', value: 'all'),
      const HomeSourceItem(label: '本地', value: 'local'),
    ];
    for (final source in _webDavSources.value) {
      items.add(
        HomeSourceItem(
          label: source.name.trim().isEmpty ? 'WebDAV' : source.name.trim(),
          value: 'webdav:${source.id}',
        ),
      );
    }
    for (final source in _navidromeSources.value) {
      items.add(
        HomeSourceItem(
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
            builder: (context) => HomeSourceTabs(
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
                  icon: const Icon(AppIcons.menu),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
          actions: [
            IconButton(
              tooltip: '管理音源',
              icon: const Icon(AppIcons.sliders),
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
                builder: (context) => HomeSourceSummary(
                  title: _filterTitle.value,
                  count: _filterCount.value,
                  loading: _loading.value,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: DiscoveryCard.height,
                child: Watch.builder(
                  builder: (context) {
                    final covers = _discoveryCovers.value;
                    final specs = <DiscoverySpec>[
                      DiscoverySpec(
                        kind: DiscoveryKind.daily,
                        eyebrow: '每日推荐',
                        title: '今日限定好歌推荐',
                        icon: AppIcons.calendar,
                        accent: const Color(0xFFEF4444),
                        cover: covers[0],
                        songs: _dailySongs.value,
                      ),
                      DiscoverySpec(
                        kind: DiscoveryKind.recommended,
                        eyebrow: '雷达歌单',
                        title: '反复聆听你爱的歌',
                        icon: null,
                        accent: const Color(0xFF38A3A5),
                        cover: covers[1],
                        songs: _recommendedSongs.value,
                      ),
                      DiscoverySpec(
                        kind: DiscoveryKind.heart,
                        eyebrow: '心动模式',
                        title: '红心歌曲和相似推荐',
                        icon: AppIconsFilled.heart,
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
                          builder: (context) => DiscoveryCard(
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
                  return HomeRecommendationSection(
                    songs: recommendedSongs,
                    onPlayAll: () => _playDiscoveryQueue(
                      recommendedSongs,
                      DiscoveryKind.recommended,
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
              HomeQuickLibrary(
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
