import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/router/app_router.dart';
import '../../app/services/artwork_service.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/local_music_service.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/router/app_page_route.dart';
import '../../app/state/settings_state.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/deferred_page_init_mixin.dart';
import '../../app/utils/page_cache_store.dart';
import '../../components/index.dart';
import '../library/library_detail_pages.dart';
import '../library/playlists_page.dart';
import 'song_detail_sheet.dart';
import 'songs_actions_controller.dart';
import 'songs_artwork_coordinator.dart';
import 'songs_selection_controller.dart';
import 'songs_visible_controller.dart';

class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SourceFilterItem {
  final String label;
  final String value;

  const _SourceFilterItem({required this.label, required this.value});
}

class _RemoveProgress {
  final int processed;
  final int total;
  final bool isRemoving;

  const _RemoveProgress({
    required this.processed,
    required this.total,
    required this.isRemoving,
  });
}

class _SongsPageState extends State<SongsPage>
    with SignalsMixin, DeferredPageInitMixin {
  static const String _prefsSourceFilter = 'songs_source_filter';
  static const String _prefsSortKey = 'songs_sort_key';
  static const String _prefsSortAsc = 'songs_sort_asc';
  static const String _prefsRandomPlayCount = 'songs_random_play_count';
  static const String _prefsSequentialPlayCount = 'songs_sequential_play_count';
  static const String _cacheScopeSongs = 'songs_all';
  static const String _cacheScopeVisible = 'songs_visible';
  static List<SongEntity>? _cachedSongs;
  static const double _itemExtent = 64;
  static const int _pageSize = 80;
  final ScrollController _listController = ScrollController();
  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final SongDao _songDao = SongDao();
  final LocalMusicService _localService = LocalMusicService();
  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final NavidromeSourceRepository _navidromeRepo =
      NavidromeSourceRepository.instance;
  final ArtworkService _artworkService = ArtworkService.instance;
  final PageCacheStore _cacheStore = PageCacheStore.instance;
  final SongsVisibleController _visibleController = SongsVisibleController();
  final SongsSelectionController _selectionController =
      SongsSelectionController();
  final SongsActionsController _actionsController = SongsActionsController();
  late final SongsArtworkCoordinator _artworkCoordinator =
      SongsArtworkCoordinator(
        artworkService: _artworkService,
        songDao: _songDao,
      );
  int _currentMaxCount = _pageSize;
  int _visibleBuildToken = 0;
  bool _cacheArtworkEnabled = false;
  bool _prefetchEnabled = false;
  Timer? _rebuildDebounceTimer;
  Timer? _artworkIdlePrefetchTimer;
  late final _selectedIds = createSignal<Set<String>>(<String>{});
  late final _visibleSongs = createSignal<List<SongEntity>>([]);
  late final _visibleSongsAll = createSignal<List<SongEntity>>([]);
  late final _multiSelect = createSignal(false);
  late final _isSequentialPlay = createSignal(false);
  late final _randomPlayCount = createSignal<int?>(null);
  late final _sequentialPlayCount = createSignal<int?>(null);
  late final _sortKey = createSignal('title');
  late final _ascending = createSignal(true);
  late final _currentId = createSignal<String?>(null);
  late final _isLoading = createSignal(true);
  late final _sourceFilter = createSignal('all');
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _webDavNameMap = createSignal<Map<String, String>>({});

  late final _isScraping = createSignal(false);
  late final _scrapeTotal = createSignal(0);
  late final _scrapeDone = createSignal(0);
  late final _scrapeSuccess = createSignal(0);
  OverlayEntry? _scrapeOverlay;
  final LayerLink _scrapeLayerLink = LayerLink();
  final ValueNotifier<_RemoveProgress> _removeNotifier = ValueNotifier(
    const _RemoveProgress(processed: 0, total: 0, isRemoving: false),
  );
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    scheduleDeferredInit();
    _listController.addListener(_handleScroll);
    PlayerService.instance.currentSong.addListener(_handlePlayerSongChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _prefetchEnabled = true;
        final visibleAll = _visibleSongsAll.value;
        if (visibleAll.isEmpty) return;
        final end = visibleAll.length - 1;
        _scheduleRangePrefetch(0, end > 9 ? 9 : end, visibleAll);
      });
    });
  }

  @override
  Future<void> runDeferredInit() async {
    await _initPage();
  }

  @override
  void dispose() {
    _rebuildDebounceTimer?.cancel();
    _artworkIdlePrefetchTimer?.cancel();
    _removeScrapeOverlay();
    PlayerService.instance.currentSong.removeListener(_handlePlayerSongChanged);
    _listController.removeListener(_handleScroll);
    _listController.dispose();
    super.dispose();
  }

  Future<void> _initPage() async {
    await _restoreViewPrefs();
    final settings = await _localService.loadSettings();
    _cacheArtworkEnabled = settings.cacheArtwork;
    unawaited(_loadWebDavNames());
    await _loadSongs();
  }

  Future<void> _loadWebDavNames() async {
    final webDavSources = await _webDavRepo.loadSources();
    final navidromeSources = await _navidromeRepo.loadSources();
    final map = <String, String>{};
    for (final s in webDavSources) {
      final name = s.name.trim().isEmpty ? 'WebDAV' : s.name.trim();
      map[s.id] = name;
    }
    for (final s in navidromeSources) {
      final name = s.name.trim().isEmpty ? 'Navidrome' : s.name.trim();
      map[s.id] = name;
    }
    if (!mounted) return;
    _webDavNameMap.value = map;
  }

  Future<void> _restoreViewPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_prefsSourceFilter);
    final sortKey = prefs.getString(_prefsSortKey);
    final sortAsc = prefs.getBool(_prefsSortAsc);
    if (!mounted) return;
    if (source != null && source.isNotEmpty) {
      _sourceFilter.value = source;
    }
    if (sortKey != null && sortKey.isNotEmpty) {
      _sortKey.value = sortKey;
    }
    if (sortAsc != null) {
      _ascending.value = sortAsc;
    }
    final randomCount = prefs.getInt(_prefsRandomPlayCount);
    if (randomCount != null && randomCount > 0) {
      _randomPlayCount.value = randomCount;
    }
    final sequentialCount = prefs.getInt(_prefsSequentialPlayCount);
    if (sequentialCount != null && sequentialCount > 0) {
      _sequentialPlayCount.value = sequentialCount;
    }
  }

  Future<void> _saveViewPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSourceFilter, _sourceFilter.value);
    await prefs.setString(_prefsSortKey, _sortKey.value);
    await prefs.setBool(_prefsSortAsc, _ascending.value);
  }

  Future<void> _loadSongs() async {
    if (_cachedSongs != null && _cachedSongs!.isNotEmpty) {
      _songs.value = _cachedSongs!;
      _seedVisibleSongsFast(_cachedSongs!);
      _isLoading.value = false;
      unawaited(_updateVisibleSongs());
    } else {
      _isLoading.value = true;
    }
    final list = await _songDao.fetchAllCached();
    if (!mounted) return;
    _cachedSongs = list;
    _cacheStore.set(_cacheScopeSongs, 'main', list);
    _songs.value = list;
    if (_visibleSongsAll.value.isEmpty) {
      _seedVisibleSongsFast(list);
    }
    if (_isLoading.value) {
      _isLoading.value = false;
    }
    unawaited(_updateVisibleSongs());
  }

  void _seedVisibleSongsFast(List<SongEntity> songs) {
    final result = _visibleController.seedVisibleSongsFast(
      songs: songs,
      sourceFilter: _sourceFilter.value,
      currentMaxCount: _currentMaxCount < _pageSize
          ? _pageSize
          : _currentMaxCount,
    );
    _visibleSongsAll.value = result.allVisible;
    if (_currentMaxCount < _pageSize) {
      _currentMaxCount = _pageSize;
    }
    if (_currentMaxCount > result.allVisible.length) {
      _currentMaxCount = result.allVisible.length;
    }
    _visibleSongs.value = result.displayVisible;
    _syncCurrentIdWithPlayer(result.allVisible);
  }

  Future<void> _updateVisibleSongs() async {
    final songs = _songs.value;
    final sourceFilter = _sourceFilter.value;
    final sortKey = _sortKey.value;
    final ascending = _ascending.value;
    final token = ++_visibleBuildToken;
    final result = await _visibleController.buildVisibleSongs(
      songs: songs,
      sourceFilter: sourceFilter,
      sortKey: sortKey,
      ascending: ascending,
      currentMaxCount: _currentMaxCount < _pageSize
          ? _pageSize
          : _currentMaxCount,
    );
    if (!mounted || token != _visibleBuildToken) return;
    _visibleSongsAll.value = result.allVisible;
    if (_currentMaxCount < _pageSize) {
      _currentMaxCount = _pageSize;
    }
    if (_currentMaxCount > result.allVisible.length) {
      _currentMaxCount = result.allVisible.length;
    }
    _visibleSongs.value = result.displayVisible;
    final prefetchEnd = _currentMaxCount - 1;
    if (prefetchEnd >= 0) {
      _scheduleRangePrefetch(
        0,
        prefetchEnd > 29 ? 29 : prefetchEnd,
        result.allVisible,
      );
    }
    _syncCurrentIdWithPlayer(result.allVisible);
  }

  void _rebuildVisibleSongs() {
    _rebuildDebounceTimer?.cancel();
    _rebuildDebounceTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      unawaited(_updateVisibleSongs());
    });
  }

  void _handleScroll() {
    final visibleAll = _visibleSongsAll.value;
    if (!_listController.hasClients || visibleAll.isEmpty) return;
    final offset = _listController.offset;
    final index = (offset / _itemExtent).floor();
    final displayCount = _visibleSongs.value.length;
    if (displayCount < visibleAll.length && index + 20 >= displayCount) {
      final next = _currentMaxCount + _pageSize;
      _currentMaxCount = next > visibleAll.length ? visibleAll.length : next;
      _visibleSongs.value = visibleAll.take(_currentMaxCount).toList();
    }
    _scheduleRangePrefetch(
      index - 4,
      index + 14,
      visibleAll,
      prunePendingOutsideRange: true,
    );
    _scheduleIdleArtworkPrefetch(index, visibleAll);
  }

  void _handlePlayerSongChanged() {
    if (!mounted) return;
    final song = PlayerService.instance.currentSong.value;
    _syncCurrentIdWithPlayer();
    if (song == null) return;
    _applySongUpdate(song);
  }

  void _syncCurrentIdWithPlayer([List<SongEntity>? visibleAll]) {
    final song = PlayerService.instance.currentSong.value;
    if (song == null) {
      if (_currentId.value != null) {
        _currentId.value = null;
      }
      return;
    }
    final list = visibleAll ?? _visibleSongsAll.value;
    final exists = list.any((s) => s.id == song.id);
    _currentId.value = exists ? song.id : null;
  }

  void _applySongUpdate(SongEntity updated) {
    final current = _songs.value;
    final idx = current.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return;

    final old = current[idx];
    final same =
        old.title == updated.title &&
        old.artist == updated.artist &&
        old.album == updated.album &&
        old.durationMs == updated.durationMs &&
        old.localCoverPath == updated.localCoverPath &&
        old.tagsParsed == updated.tagsParsed;
    if (same) return;

    if (old.localCoverPath != updated.localCoverPath) {
      _artworkCoordinator.clearSong(updated.id, uri: updated.uri);
    }

    final next = List<SongEntity>.from(current);
    next[idx] = updated;
    _songs.value = next;
    _cachedSongs = next;
    unawaited(_updateVisibleSongs());
  }

  String _indexLabelForSong(SongEntity song) {
    switch (_sortKey.value) {
      case 'artist':
        final artist = song.artist.trim();
        if (artist.isEmpty || artist == '未知艺术家') return '↑';
        return IndexUtils.leadingLetter(artist);
      case 'album':
        final album = (song.album ?? '').trim();
        if (album.isEmpty || album == '未知专辑') return '↑';
        return IndexUtils.leadingLetter(album);
      case 'duration':
        return IndexUtils.leadingLetter(song.title);
      case 'title':
      default:
        final title = song.title.trim();
        if (title.isEmpty || title == '未知标题') return '↑';
        return IndexUtils.leadingLetter(title);
    }
  }

  void _toggleSelectAll(List<SongEntity> visible) {
    _selectedIds.value = _selectionController.toggleSelectAll(
      _selectedIds.value,
      visible,
    );
  }

  void _toggleMultiSelect() {
    _multiSelect.value = _selectionController.toggleMultiSelect(
      _multiSelect.value,
    );
    _selectedIds.value = _selectionController.clearSelection();
  }

  Future<void> _openAddToPlaylistSheet() async {
    final added = await _actionsController.addSelectedToPlaylist(
      selectedIds: _selectedIds.value,
      openDialog: (songIds) =>
          showAddToPlaylistDialog(context, songIds: songIds),
    );
    if (!mounted) return;
    if (added) {
      _toggleMultiSelect();
    }
  }

  void _togglePlayMode() {
    HapticFeedback.mediumImpact();
    _isSequentialPlay.value = !_isSequentialPlay.value;
    AppToast.show(context, _isSequentialPlay.value ? '已切换为顺序播放' : '已切换为随机播放');
  }

  int _playCountForMode(int totalCount) {
    if (totalCount <= 0) return 0;
    final configured = _isSequentialPlay.value
        ? _sequentialPlayCount.value
        : _randomPlayCount.value;
    return configured == null ? totalCount : configured.clamp(1, totalCount);
  }

  int _configuredOrAllCount(int? configured, int totalCount) {
    if (totalCount <= 0) return 0;
    return configured == null ? totalCount : configured.clamp(1, totalCount);
  }

  List<SongEntity> _buildPlayQueue(
    List<SongEntity> source, {
    String? targetSongId,
  }) {
    final queue = List<SongEntity>.from(source);
    if (_isSequentialPlay.value) {
      final maxCount = _configuredOrAllCount(
        _sequentialPlayCount.value,
        queue.length,
      );
      if (targetSongId == null || targetSongId.isEmpty) {
        return queue.take(maxCount).toList();
      }
      final startIndex = queue.indexWhere((song) => song.id == targetSongId);
      if (startIndex < 0) {
        return queue.take(maxCount).toList();
      }
      return queue.skip(startIndex).take(maxCount).toList();
    }
    queue.shuffle();
    final maxCount = _configuredOrAllCount(
      _randomPlayCount.value,
      queue.length,
    );
    final limited = queue.take(maxCount).toList();
    if (targetSongId == null || targetSongId.isEmpty) {
      return limited;
    }
    final existingIndex = limited.indexWhere((song) => song.id == targetSongId);
    if (existingIndex >= 0) {
      return limited;
    }
    final original = source.where((song) => song.id == targetSongId).toList();
    if (original.isEmpty) {
      return limited;
    }
    if (limited.isEmpty) {
      return [original.first];
    }
    return [original.first, ...limited.take(maxCount - 1)];
  }

  Future<void> _showPlayCountSettings({
    required String title,
    required String description,
    required int? initialCount,
    required String successMessage,
    required Future<void> Function(int next) onSave,
  }) async {
    if (_visibleSongsAll.value.isEmpty) return;
    final maxCount = _visibleSongsAll.value.length.clamp(1, 200);
    var tempCount = _configuredOrAllCount(initialCount, maxCount).toDouble();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AppSheetPanel(
              title: title,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LabeledSlider(
                      title: '播放数量',
                      value: tempCount.clamp(1, maxCount).toDouble(),
                      min: 1,
                      max: maxCount.toDouble(),
                      divisions: maxCount > 1 ? maxCount - 1 : 1,
                      valueText: '${tempCount.round()} 首',
                      description: description,
                      onChanged: (value) {
                        setModalState(() {
                          tempCount = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final navigator = Navigator.of(sheetContext);
                          final next = tempCount.round().clamp(1, maxCount);
                          await onSave(next);
                          if (!mounted) return;
                          navigator.pop();
                          AppToast.show(
                            this.context,
                            '$successMessage $next 首',
                          );
                        },
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showRandomPlaySettings() {
    return _showPlayCountSettings(
      title: '随机播放设置',
      description: '未设置时默认随机播放全部歌曲',
      initialCount: _randomPlayCount.value,
      successMessage: '随机播放数量已设为',
      onSave: (next) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsRandomPlayCount, next);
        _randomPlayCount.value = next;
      },
    );
  }

  Future<void> _showSequentialPlaySettings() {
    return _showPlayCountSettings(
      title: '顺序播放设置',
      description: '未设置时默认顺序播放全部歌曲',
      initialCount: _sequentialPlayCount.value,
      successMessage: '顺序播放数量已设为',
      onSave: (next) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsSequentialPlayCount, next);
        _sequentialPlayCount.value = next;
      },
    );
  }

  Future<void> _showCurrentPlaySettings() {
    if (_isSequentialPlay.value) {
      return _showSequentialPlaySettings();
    }
    return _showRandomPlaySettings();
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openSearch() {
    Navigator.pushNamed(context, AppRoutes.search);
  }

  void _removeScrapeOverlay() {
    _scrapeOverlay?.remove();
    _scrapeOverlay = null;
  }

  void _showRemoveDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return ValueListenableBuilder<_RemoveProgress>(
          valueListenable: _removeNotifier,
          builder: (context, progress, child) {
            final finished = !progress.isRemoving;
            return AppDialog(
              title: finished ? '移除完成' : '正在移除...',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: progress.total > 0
                        ? progress.processed / progress.total
                        : 0,
                  ),
                  const SizedBox(height: 16),
                  Text('已移除: ${progress.processed}'),
                  const SizedBox(height: 4),
                  Text('总计: ${progress.total}'),
                ],
              ),
              confirmText: finished ? '知道了' : '隐藏',
              showCancel: false,
              onConfirm: () {},
            );
          },
        );
      },
    );
  }

  void _showScrapeOverlay() {
    _removeScrapeOverlay();
    final overlay = Overlay.of(context);
    _scrapeOverlay = OverlayEntry(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final total = _scrapeTotal.value;
        final done = _scrapeDone.value;
        final success = _scrapeSuccess.value;
        return Positioned(
          width: 300,
          child: CompositedTransformFollower(
            link: _scrapeLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(-250, 45),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: scheme.primary,
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isScraping.value ? '正在刮削' : '刮削完成',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        InkWell(
                          onTap: _removeScrapeOverlay,
                          child: Icon(
                            Icons.close,
                            color: scheme.onPrimary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '待更新 $total，剩余 ${total - done}，已更新 $success',
                      style: TextStyle(color: scheme.onPrimary, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total > 0 ? done / total : 0,
                      backgroundColor: scheme.onPrimary.withValues(alpha: 0.22),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_scrapeOverlay!);
  }

  void _updateScrapeOverlay() {
    _scrapeOverlay?.markNeedsBuild();
  }

  Future<void> _openBatchScrape() async {
    if (_isScraping.value) {
      _showScrapeOverlay();
      return;
    }

    final visible = _visibleSongsAll.value;
    final selected = _selectedIds.value;
    final candidates = _multiSelect.value && selected.isNotEmpty
        ? visible.where((s) => selected.contains(s.id)).toList()
        : visible;
    if (candidates.isEmpty) {
      AppToast.show(context, '列表为空');
      return;
    }

    final toScrape = await _actionsController.collectSongsToScrape(candidates);
    if (toScrape.isEmpty) {
      if (!mounted) return;
      AppToast.show(context, '无需刮削');
      return;
    }

    if (!mounted) return;
    _isScraping.value = true;
    _scrapeTotal.value = toScrape.length;
    _scrapeDone.value = 0;
    _scrapeSuccess.value = 0;
    _showScrapeOverlay();

    await _actionsController.scrapeSongs(
      songs: toScrape,
      onSongUpdated: (updated) async {
        if (!mounted) return;
        _applySongUpdate(updated);
      },
      onProgress: (done, success, total) async {
        if (!mounted) return;
        _scrapeDone.value = done;
        _scrapeSuccess.value = success;
        _scrapeTotal.value = total;
        _updateScrapeOverlay();
      },
    );

    if (!mounted) return;
    _isScraping.value = false;
    _updateScrapeOverlay();
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _removeScrapeOverlay();
  }

  void _scheduleRangePrefetch(
    int start,
    int end,
    List<SongEntity> songs, {
    bool prunePendingOutsideRange = false,
  }) {
    _artworkCoordinator.scheduleRangePrefetch(
      start,
      end,
      songs,
      enabled: _prefetchEnabled,
      sourceFilter: _sourceFilter.value,
      sortKey: _sortKey.value,
      ascending: _ascending.value,
      cacheArtworkEnabled: _cacheArtworkEnabled,
      prunePendingOutsideRange: prunePendingOutsideRange,
      onSongUpdated: _applySongUpdate,
    );
  }

  void _scheduleIdleArtworkPrefetch(int index, List<SongEntity> songs) {
    _artworkIdlePrefetchTimer?.cancel();
    _artworkIdlePrefetchTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _scheduleRangePrefetch(index - 10, index + 50, songs);
    });
  }

  Future<void> _showSourceSheet() async {
    await _loadWebDavNames();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final items = [
          const _SourceFilterItem(label: '全部', value: 'all'),
          const _SourceFilterItem(label: '本地', value: 'local'),
          const _SourceFilterItem(label: '云端（全部）', value: 'webdav'),
        ];
        final webdavIds =
            _songs.value
                .map((song) => song.sourceId ?? '')
                .where((id) => id.isNotEmpty && id != 'local')
                .toSet()
                .toList()
              ..sort();

        return AppSheetPanel(
          title: '切换音源',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...items.map((item) {
                final isSelected = _sourceFilter.value == item.value;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(item.label),
                  trailing: isSelected ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    _sourceFilter.value = item.value;
                    _rebuildVisibleSongs();
                    _saveViewPrefs();
                    Navigator.pop(context);
                  },
                );
              }),
              if (webdavIds.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 24),
                  title: Text('暂无云端音源'),
                  enabled: false,
                )
              else
                ...webdavIds.map((id) {
                  final value = 'webdav:$id';
                  final isSelected = _sourceFilter.value == value;
                  final name = _webDavNameMap.value[id];
                  final label = (name ?? id).trim();
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text('云端：$label'),
                    trailing: isSelected
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () {
                      _sourceFilter.value = value;
                      _rebuildVisibleSongs();
                      _saveViewPrefs();
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

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) {
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final tabletOverlayInset = AppLayoutSettings.tabletMode.value
            ? MiniPlayerBar.estimatedHeight + bottomInset + 16
            : 0.0;
        return Padding(
          padding: EdgeInsets.only(bottom: tabletOverlayInset),
          child: SortSheet(
            options: const [
              SortOption(
                key: 'title',
                label: '歌曲名称',
                icon: Icons.sort_by_alpha,
              ),
              SortOption(
                key: 'artist',
                label: '歌手名称',
                icon: Icons.person_outline,
              ),
              SortOption(
                key: 'album',
                label: '专辑名称',
                icon: Icons.album_outlined,
              ),
              SortOption(key: 'duration', label: '歌曲时长', icon: Icons.schedule),
            ],
            currentKey: _sortKey.value,
            ascending: _ascending.value,
            onSelectKey: (value) {
              _sortKey.value = value;
              _rebuildVisibleSongs();
              _saveViewPrefs();
            },
            onSelectAscending: (value) {
              _ascending.value = value;
              _rebuildVisibleSongs();
              _saveViewPrefs();
            },
          ),
        );
      },
    );
  }

  String _durationText(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '--:--';
    final totalSeconds = (durationMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _openPlayerWithQueue(
    List<SongEntity> queue,
    int startIndex,
  ) async {
    if (queue.isEmpty) return;
    await PlayerService.instance.playQueue(queue, startIndex);
  }

  Future<void> _removeSelectedSongs() async {
    if (_isRemoving) {
      _showRemoveDialog();
      return;
    }
    final ids = _selectedIds.value.toList(growable: false);
    if (ids.isEmpty) return;
    final removedSongs = _songs.value
        .where((s) => ids.contains(s.id))
        .toList(growable: false);
    _isRemoving = true;
    _removeNotifier.value = _RemoveProgress(
      processed: 0,
      total: removedSongs.length,
      isRemoving: true,
    );
    _showRemoveDialog();
    var processed = 0;
    final removedCount = await _actionsController.removeSongs(
      songsToRemove: removedSongs,
      clearArtwork: (song) =>
          _artworkCoordinator.clearSong(song.id, uri: song.uri),
      onSongsRemoved: (removedBatch) async {
        if (!mounted) return;
        final removedIds = removedBatch.map((e) => e.id).toSet();
        final nextSongs = _songs.value
            .where((s) => !removedIds.contains(s.id))
            .toList();
        _songs.value = nextSongs;
        _cachedSongs = nextSongs;
        _visibleSongs.value = _visibleSongs.value
            .where((s) => !removedIds.contains(s.id))
            .toList();
        _visibleSongsAll.value = _visibleSongsAll.value
            .where((s) => !removedIds.contains(s.id))
            .toList();
        if (removedIds.contains(_currentId.value)) {
          _currentId.value = null;
        }
        final nextSelected = Set<String>.from(_selectedIds.value)
          ..removeAll(removedIds);
        _selectedIds.value = nextSelected;
      },
      onProgress: (nextProcessed, total) async {
        if (!mounted) return;
        processed = nextProcessed;
        _removeNotifier.value = _RemoveProgress(
          processed: nextProcessed,
          total: total,
          isRemoving: true,
        );
      },
    );
    if (!mounted) return;
    _cacheStore.clearScope(_cacheScopeVisible);
    _isRemoving = false;
    _removeNotifier.value = _RemoveProgress(
      processed: processed,
      total: removedSongs.length,
      isRemoving: false,
    );
    AppToast.show(context, '已移除 $removedCount 首');
    _selectedIds.value = _selectionController.clearSelection();
    _multiSelect.value = false;
    unawaited(_updateVisibleSongs());
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final isTabletLandscape =
            AppLayoutSettings.tabletMode.value &&
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final tabletMiniPlayerInset = AppLayoutSettings.tabletMode.value
            ? MiniPlayerBar.estimatedHeight + bottomInset + 12
            : 0.0;
        if (_isLoading.value) {
          return AppPageScaffold(
            key: _scaffoldKey,
            extendBodyBehindAppBar: true,
            showMiniPlayer: !_multiSelect.value,
            appBar: AppTopBar(
              title: '歌曲',
              centerTitle: !isTabletLandscape,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: _openDrawer,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onPressed: _showSourceSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                CompositedTransformTarget(
                  link: _scrapeLayerLink,
                  child: IconButton(
                    icon: _isScraping.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_rounded),
                    onPressed: _openBatchScrape,
                  ),
                ),
              ],
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            drawer: const SideMenu(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final visibleSongs = _visibleSongs.value;
        final totalCount = _visibleSongsAll.value.length;
        final selectedCount = _selectionController.selectedCount(
          _selectedIds.value,
        );
        final isAllSelected = totalCount > 0 && selectedCount == totalCount;

        return AppPageScaffold(
          key: _scaffoldKey,
          extendBodyBehindAppBar: true,
          showMiniPlayer: !_multiSelect.value,
          appBar: AppTopBar(
            title: '歌曲',
            centerTitle: !isTabletLandscape,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: _openDrawer,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: _showSourceSheet,
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _openSearch,
              ),
              CompositedTransformTarget(
                link: _scrapeLayerLink,
                child: IconButton(
                  icon: _isScraping.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  onPressed: _openBatchScrape,
                ),
              ),
            ],
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          drawer: SideMenu(
            onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
          body: Column(
            children: [
              MediaListHeader(
                multiSelect: _multiSelect.value,
                isAllSelected: isAllSelected,
                selectedCount: selectedCount,
                totalCount: totalCount,
                playbackCount: _playCountForMode(totalCount),
                isSequentialPlay: _isSequentialPlay.value,
                onToggleSelectAll: () =>
                    _toggleSelectAll(_visibleSongsAll.value),
                onPlay: () {
                  if (_visibleSongsAll.value.isEmpty) return;
                  final queue = _buildPlayQueue(_visibleSongsAll.value);
                  _openPlayerWithQueue(queue, 0);
                },
                onConfigurePlay: _showCurrentPlaySettings,
                onTogglePlayMode: _togglePlayMode,
                onSort: _showSortSheet,
                onToggleMultiSelect: _toggleMultiSelect,
              ),
              Expanded(
                child: totalCount == 0
                    ? const Center(child: Text('暂无歌曲'))
                    : MediaListView(
                        controller: _listController,
                        itemCount: visibleSongs.length,
                        itemExtent: _itemExtent,
                        bottomInset:
                            bottomInset +
                            tabletMiniPlayerInset +
                            (_multiSelect.value ? 160 : 80),
                        indexLabelBuilder: (index) =>
                            _indexLabelForSong(visibleSongs[index]),
                        itemBuilder: (context, index) {
                          final song = visibleSongs[index];
                          final currentId = _currentId.value;
                          final selected = _selectedIds.value;
                          final isPlaying = currentId == song.id;
                          return MediaListTile(
                            leading: _SongArtwork(
                              song: song,
                              size: 44,
                              coverPath: song.localCoverPath,
                              onLoad: () => _loadArtwork(song),
                            ),
                            title: song.title,
                            subtitle:
                                '${song.artist} · ${song.album ?? '未知专辑'} · ${_durationText(song.durationMs)}',
                            selected: selected.contains(song.id),
                            multiSelect: _multiSelect.value,
                            isHighlighted: isPlaying,
                            onTap: () {
                              if (_multiSelect.value) {
                                _selectedIds.value = _selectionController
                                    .toggleSong(selected, song.id);
                              } else {
                                _currentId.value = song.id;
                                final queue = _buildPlayQueue(
                                  _visibleSongsAll.value,
                                  targetSongId: song.id,
                                );
                                final startIndex = queue.indexWhere(
                                  (s) => s.id == song.id,
                                );
                                _openPlayerWithQueue(
                                  queue,
                                  startIndex == -1 ? 0 : startIndex,
                                );
                              }
                            },
                            onLongPress: () {
                              if (_multiSelect.value) {
                                _selectedIds.value = _selectionController
                                    .toggleSong(selected, song.id);
                                return;
                              }

                              showModalBottomSheet<void>(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) {
                                  return SongDetailSheet(
                                    song: song,
                                    onOpenArtist: (artistName) {
                                      Navigator.of(context).push(
                                        buildAppPageRoute(
                                          (_) => ArtistDetailPage(
                                            artistName: artistName,
                                          ),
                                        ),
                                      );
                                    },
                                    onOpenAlbum: (albumName) {
                                      Navigator.of(context).push(
                                        buildAppPageRoute(
                                          (_) => AlbumDetailPage(
                                            albumName: albumName,
                                          ),
                                        ),
                                      );
                                    },
                                    onUpdated: (updated) {
                                      if (!mounted) return;
                                      final updatedSongs = _songs.value
                                          .map(
                                            (s) => s.id == updated.id
                                                ? updated
                                                : s,
                                          )
                                          .toList();
                                      _songs.value = updatedSongs;
                                      _cachedSongs = updatedSongs;
                                      unawaited(_updateVisibleSongs());
                                    },
                                    onDeleted: (id) {
                                      if (!mounted) return;
                                      final currentSongs = _songs.value;
                                      SongEntity? deleted;
                                      for (final s in currentSongs) {
                                        if (s.id == id) {
                                          deleted = s;
                                          break;
                                        }
                                      }
                                      final nextSongs = currentSongs
                                          .where((s) => s.id != id)
                                          .toList();
                                      _songs.value = nextSongs;
                                      _cachedSongs = nextSongs;
                                      if (_currentId.value == id) {
                                        _currentId.value = null;
                                      }
                                      unawaited(_updateVisibleSongs());
                                      if (deleted != null) {
                                        Future.microtask(
                                          () => _actionsController.removeSongs(
                                            songsToRemove: [deleted!],
                                            clearArtwork: (song) =>
                                                _artworkCoordinator.clearSong(
                                                  song.id,
                                                  uri: song.uri,
                                                ),
                                            onSongsRemoved: (removed) async {},
                                            onProgress:
                                                (processed, total) async {},
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                        floatingButton: _currentId.value == null
                            ? null
                            : FloatingActionButton(
                                mini: true,
                                onPressed: () {
                                  final targetId = _currentId.value;
                                  if (targetId == null) return;
                                  final index = visibleSongs.indexWhere(
                                    (s) => s.id == targetId,
                                  );
                                  if (index == -1) return;
                                  final offset = index * _itemExtent;
                                  final max =
                                      _listController.position.maxScrollExtent;
                                  _listController.animateTo(
                                    offset.clamp(0.0, max),
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeOut,
                                  );
                                },
                                child: const Icon(Icons.my_location, size: 18),
                              ),
                      ),
              ),
              if (_multiSelect.value)
                Padding(
                  padding: EdgeInsets.only(bottom: tabletMiniPlayerInset),
                  child: MultiSelectBottomBar(
                    actions: [
                      MultiSelectAction(
                        icon: Icons.queue_play_next,
                        label: '下一首播放',
                        onTap: selectedCount == 0
                            ? null
                            : () {
                                AppToast.show(
                                  context,
                                  '已添加 $selectedCount 首到下一首播放',
                                );
                                _toggleMultiSelect();
                              },
                      ),
                      MultiSelectAction(
                        icon: Icons.playlist_add,
                        label: '收藏到歌单',
                        onTap: selectedCount == 0
                            ? null
                            : _openAddToPlaylistSheet,
                      ),
                      MultiSelectAction(
                        icon: Icons.delete_outline,
                        label: '移除',
                        isDestructive: true,
                        onTap: selectedCount == 0 ? null : _removeSelectedSongs,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Uint8List?> _loadArtwork(SongEntity song) {
    return _artworkCoordinator.loadArtwork(
      song,
      cacheArtworkEnabled: _cacheArtworkEnabled,
      onSongUpdated: _applySongUpdate,
    );
  }
}

class _SongArtwork extends StatefulWidget {
  final SongEntity song;
  final double size;
  final String? coverPath;
  final Future<Uint8List?> Function()? onLoad;

  const _SongArtwork({
    required this.song,
    required this.size,
    required this.coverPath,
    required this.onLoad,
  });

  @override
  State<_SongArtwork> createState() => _SongArtworkState();
}

class _SongArtworkState extends State<_SongArtwork> with SignalsMixin {
  late final _bytes = createSignal<Uint8List?>(null);

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _SongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final coverChanged = oldWidget.coverPath != widget.coverPath;
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.uri != widget.song.uri ||
        coverChanged) {
      _bytes.value = null;
      _resolve();
    }
  }

  void _resolve() {
    if (widget.coverPath != null && widget.coverPath!.isNotEmpty) return;
    final loader = widget.onLoad;
    if (loader == null) return;
    loader().then((bytes) {
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        _bytes.value = bytes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final coverPath = widget.coverPath;
        if (coverPath != null && coverPath.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(coverPath),
              width: widget.size,
              height: widget.size,
              cacheWidth:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt(),
              cacheHeight:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _SongArtworkPlaceholder(song: widget.song);
              },
            ),
          );
        }
        final bytes = _bytes.value;
        if (bytes != null && bytes.isNotEmpty) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              cacheWidth:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt(),
              cacheHeight:
                  (widget.size * MediaQuery.of(context).devicePixelRatio)
                      .toInt(),
              fit: BoxFit.cover,
            ),
          );
        }
        return _SongArtworkPlaceholder(song: widget.song);
      },
    );
  }
}

class _SongArtworkPlaceholder extends StatelessWidget {
  final SongEntity song;

  const _SongArtworkPlaceholder({required this.song});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        song.title.isEmpty ? '?' : song.title.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
