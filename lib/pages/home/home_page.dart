import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/state/settings_state.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/router/app_page_route.dart';
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
import '../library/albums_page.dart';
import '../library/artists_page.dart';
import '../library/library_detail_pages.dart';
import '../library/playlists_page.dart';
import 'recent_playback_page.dart';
import '../songs/songs_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
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
    _load();
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
    final recentPlaylistsFuture = _loadRecentPlaylists();

    final counts = await countsFuture;
    final sources = await sourcesFuture;
    final navidromeSources = await navidromeSourcesFuture;
    final recentSongs = await recentSongsFuture;
    final recentPlaylists = await recentPlaylistsFuture;
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
    _recentPlaylists.value = recentPlaylists;
    _recentAlbums.value = recentAlbums;
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

  Future<List<PlaylistEntity>> _loadRecentPlaylists() async {
    final playlists = await _playlistsService.loadAll();
    final sorted = playlists.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return sorted.take(6).toList();
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

  Future<void> _pushLibraryPage(Widget page) async {
    await Navigator.of(context).push(buildAppPageRoute<void>((_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '首页',
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: _showSourceSheet,
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: SideMenu(
        onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      body: Watch.builder(
        builder: (context) => RefreshIndicator(
          onRefresh: () => _load(includeWebDavCounts: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
            children: [
              Text(
                '音乐库',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _HomeStatsRow(
                loading: _loading.value,
                filterLabel: _filterTitle.value,
                songCount: _filterCount.value,
                onTap: _showSourceSheet,
              ),
              const SizedBox(height: 14),
              _HomeEntryRow(
                entries: [
                  _HomeEntryData(
                    icon: Icons.music_note_rounded,
                    label: '歌曲',
                    onTap: () => _pushLibraryPage(const SongsPage()),
                  ),
                  _HomeEntryData(
                    icon: Icons.people_rounded,
                    label: '艺术家',
                    onTap: () => _pushLibraryPage(const ArtistsPage()),
                  ),
                  _HomeEntryData(
                    icon: Icons.album_rounded,
                    label: '专辑',
                    onTap: () => _pushLibraryPage(const AlbumsPage()),
                  ),
                  _HomeEntryData(
                    icon: Icons.queue_music_rounded,
                    label: '歌单',
                    onTap: () => _pushLibraryPage(const PlaylistsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _HomeSectionCard(
                title: '最近歌曲',
                actionLabel: '查看更多',
                onTapAction: () {
                  _pushLibraryPage(
                    const RecentPlaybackPage(
                      initialTab: RecentPlaybackTab.songs,
                    ),
                  );
                },
                child: _HomeRecentSongsList(
                  songs: _recentSongs.value,
                  onTapSong: (song) async {
                    final queue = _recentSongs.value;
                    final index = queue.indexWhere((e) => e.id == song.id);
                    if (index < 0) return;
                    await _player.playQueue(queue, index);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _HomeSectionCard(
                title: '最近歌单',
                actionLabel: '查看更多',
                onTapAction: () {
                  _pushLibraryPage(
                    const RecentPlaybackPage(
                      initialTab: RecentPlaybackTab.playlists,
                    ),
                  );
                },
                child: _HomeRecentPlaylistsList(
                  playlists: _recentPlaylists.value,
                  onTapPlaylist: (playlist) {
                    _pushLibraryPage(
                      PlaylistDetailPage(playlistId: playlist.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _HomeSectionCard(
                title: '最近专辑',
                actionLabel: '查看更多',
                onTapAction: () {
                  _pushLibraryPage(
                    const RecentPlaybackPage(
                      initialTab: RecentPlaybackTab.albums,
                    ),
                  );
                },
                child: _HomeRecentAlbumsList(
                  albums: _recentAlbums.value,
                  onTapAlbum: (album) {
                    _pushLibraryPage(AlbumDetailPage(albumName: album.name));
                  },
                ),
              ),
            ],
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

class _HomeStatsRow extends StatelessWidget {
  final bool loading;
  final String filterLabel;
  final int songCount;
  final VoidCallback? onTap;

  const _HomeStatsRow({
    required this.loading,
    required this.filterLabel,
    required this.songCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassPanel(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.library_music_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              filterLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (loading)
            Text(
              '--',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          else
            Text(
              '$songCount 首',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _HomeSourceItem {
  final String label;
  final String value;

  const _HomeSourceItem({required this.label, required this.value});
}

class _HomeEntryData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeEntryData({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _HomeEntryRow extends StatelessWidget {
  final List<_HomeEntryData> entries;

  const _HomeEntryRow({required this.entries});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: entries
            .map(
              (entry) => Expanded(
                child: _HomeEntryButton(
                  icon: entry.icon,
                  label: entry.label,
                  onTap: entry.onTap,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HomeEntryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeEntryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.9)
        : theme.colorScheme.primary;
    final textColor = isDark
        ? Colors.white
        : const Color.fromARGB(255, 45, 45, 45);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSectionCard extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onTapAction;
  final Widget child;

  const _HomeSectionCard({
    required this.title,
    required this.actionLabel,
    required this.onTapAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTapAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _HomeRecentSongsList extends StatelessWidget {
  final List<SongEntity> songs;
  final ValueChanged<SongEntity> onTapSong;

  const _HomeRecentSongsList({required this.songs, required this.onTapSong});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return _HomeEmptyState(text: '还没有最近播放记录');
    }
    return Column(
      children: songs.map((song) {
        final subtitle = [
          song.artist.trim(),
          (song.album ?? '').trim(),
        ].where((e) => e.isNotEmpty).join(' · ');
        return AppListTile(
          leading: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ArtworkWidget(
              song: song,
              size: 44,
              borderRadius: 10,
              placeholder: _ArtworkPlaceholder(
                label: song.title.isEmpty ? '?' : song.title.substring(0, 1),
              ),
            ),
          ),
          title: song.title,
          subtitle: subtitle.isEmpty ? '未知信息' : subtitle,
          onTap: () => onTapSong(song),
        );
      }).toList(),
    );
  }
}

class _HomeRecentPlaylistsList extends StatelessWidget {
  final List<PlaylistEntity> playlists;
  final ValueChanged<PlaylistEntity> onTapPlaylist;

  const _HomeRecentPlaylistsList({
    required this.playlists,
    required this.onTapPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return _HomeEmptyState(text: '还没有可展示的最近歌单');
    }
    return Column(
      children: playlists.map((playlist) {
        final subtitle = playlist.isFavorite
            ? '我喜欢 · ${playlist.songIds.length} 首'
            : '${playlist.songIds.length} 首';
        return AppListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              playlist.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.queue_music_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: playlist.name,
          subtitle: subtitle,
          onTap: () => onTapPlaylist(playlist),
        );
      }).toList(),
    );
  }
}

class _HomeRecentAlbumsList extends StatelessWidget {
  final List<_RecentAlbumItem> albums;
  final ValueChanged<_RecentAlbumItem> onTapAlbum;

  const _HomeRecentAlbumsList({required this.albums, required this.onTapAlbum});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return _HomeEmptyState(text: '还没有最近播放过的专辑');
    }
    return Column(
      children: albums.map((album) {
        final artist = album.representative.artist.trim();
        return AppListTile(
          leading: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ArtworkWidget(
              song: album.representative,
              size: 44,
              borderRadius: 10,
              placeholder: _ArtworkPlaceholder(
                label: album.name.isEmpty ? '?' : album.name.substring(0, 1),
              ),
            ),
          ),
          title: album.name,
          subtitle: artist.isEmpty ? '未知艺术家' : artist,
          onTap: () => onTapAlbum(album),
        );
      }).toList(),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  final String text;

  const _HomeEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.62),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  final String label;

  const _ArtworkPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
