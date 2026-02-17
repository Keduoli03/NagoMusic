import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;


import '../../app/router/app_router.dart';
import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/cache/audio_cache_service.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/local_music_service.dart';
import '../../app/services/metadata/tag_probe_service.dart';
import '../../app/services/player_service.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import '../library/library_detail_pages.dart';
import '../library/playlists_page.dart';
import 'song_detail_sheet.dart';

class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SourceFilterItem {
  final String label;
  final String value;

  const _SourceFilterItem({
    required this.label,
    required this.value,
  });
}

class _ArtworkTask {
  final SongEntity song;
  final Completer<Uint8List?> completer;

  _ArtworkTask(this.song, this.completer);
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

class _SongsPageState extends State<SongsPage> with SignalsMixin {
  static const String _prefsSourceFilter = 'songs_source_filter';
  static const String _prefsSortKey = 'songs_sort_key';
  static const String _prefsSortAsc = 'songs_sort_asc';
  static List<SongEntity>? _cachedSongs;
  static List<SongEntity>? _cachedVisibleAll;
  static List<SongEntity>? _cachedVisibleSongsRef;
  static String? _cachedVisibleKey;
  static final LinkedHashMap<String, Uint8List> _artworkCache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _artworkLoading = {};
  static final List<_ArtworkTask> _artworkQueue = [];
  static int _artworkActive = 0;
  static const int _artworkMaxConcurrent = 12;
  static const int _artworkCacheMax = 300;
  static const double _itemExtent = 64;
  static const int _pageSize = 80;
  final ScrollController _listController = ScrollController();
  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final SongDao _songDao = SongDao();
  final LocalMusicService _localService = LocalMusicService();
  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  String _lastPrefetchKey = '';
  int _lastPrefetchCount = -1;
  int _currentMaxCount = _pageSize;
  int _visibleBuildToken = 0;
  bool _cacheArtworkEnabled = false;
  late final _selectedIds = createSignal<Set<String>>(<String>{});
  late final _visibleSongs = createSignal<List<SongEntity>>([]);
  late final _visibleSongsAll = createSignal<List<SongEntity>>([]);
  late final _multiSelect = createSignal(false);
  late final _isSequentialPlay = createSignal(false);
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
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final AudioCacheService _audioCache = AudioCacheService.instance;
  final ValueNotifier<_RemoveProgress> _removeNotifier =
      ValueNotifier(const _RemoveProgress(processed: 0, total: 0, isRemoving: false));
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _initPage();
    _listController.addListener(_handleScroll);
    PlayerService.instance.currentSong.addListener(_handlePlayerSongChanged);
  }

  @override
  void dispose() {
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
    await _loadWebDavNames();
    await _loadSongs();
  }

  Future<void> _loadWebDavNames() async {
    final sources = await _webDavRepo.loadSources();
    final map = <String, String>{};
    for (final s in sources) {
      final name = s.name.trim().isEmpty ? 'WebDAV' : s.name.trim();
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
      _isLoading.value = false;
      await _updateVisibleSongs();
    } else {
      _isLoading.value = true;
    }
    final list = await _songDao.fetchAllCached();
    if (!mounted) return;
    _cachedSongs = list;
    _songs.value = list;
    await _updateVisibleSongs();
    if (!mounted) return;
    _isLoading.value = false;
  }

  Future<void> _updateVisibleSongs() async {
    final songs = _songs.value;
    final sourceFilter = _sourceFilter.value;
    final sortKey = _sortKey.value;
    final ascending = _ascending.value;
    final cacheKey = '$sourceFilter|$sortKey|${ascending ? 1 : 0}';
    final cached = _cachedVisibleAll;
    if (cached != null &&
        identical(_cachedVisibleSongsRef, songs) &&
        _cachedVisibleKey == cacheKey) {
      _visibleSongsAll.value = cached;
      if (_currentMaxCount < _pageSize) {
        _currentMaxCount = _pageSize;
      }
      if (_currentMaxCount > cached.length) {
        _currentMaxCount = cached.length;
      }
      _visibleSongs.value = cached.take(_currentMaxCount).toList();
      final prefetchEnd = _currentMaxCount - 1;
      if (prefetchEnd >= 0) {
        _scheduleRangePrefetch(0, prefetchEnd > 29 ? 29 : prefetchEnd, cached);
      }
      return;
    }
    final token = ++_visibleBuildToken;
    final visible = await _buildVisibleSongsAsync(
      songs: songs,
      sourceFilter: sourceFilter,
      sortKey: sortKey,
      ascending: ascending,
    );
    if (!mounted || token != _visibleBuildToken) return;
    _cachedVisibleAll = visible;
    _cachedVisibleSongsRef = songs;
    _cachedVisibleKey = cacheKey;
    _visibleSongsAll.value = visible;
    if (_currentMaxCount < _pageSize) {
      _currentMaxCount = _pageSize;
    }
    if (_currentMaxCount > visible.length) {
      _currentMaxCount = visible.length;
    }
    _visibleSongs.value = visible.take(_currentMaxCount).toList();
    final prefetchEnd = _currentMaxCount - 1;
    if (prefetchEnd >= 0) {
      _scheduleRangePrefetch(0, prefetchEnd > 29 ? 29 : prefetchEnd, visible);
    }
  }

  void _rebuildVisibleSongs() {
    unawaited(_updateVisibleSongs());
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
    _scheduleRangePrefetch(index - 6, index + 24, visibleAll);
  }

  void _handlePlayerSongChanged() {
    if (!mounted) return;
    final song = PlayerService.instance.currentSong.value;
    if (song == null) return;
    _applySongUpdate(song);
  }

  void _applySongUpdate(SongEntity updated) {
    final current = _songs.value;
    final idx = current.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return;

    final old = current[idx];
    final same = old.title == updated.title &&
        old.artist == updated.artist &&
        old.album == updated.album &&
        old.durationMs == updated.durationMs &&
        old.localCoverPath == updated.localCoverPath &&
        old.tagsParsed == updated.tagsParsed;
    if (same) return;

    if (old.localCoverPath != updated.localCoverPath) {
      _artworkCache.remove(updated.id);
      _artworkLoading.remove(updated.id);
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
    if (visible.isEmpty) return;
    final current = _selectedIds.value;
    if (current.length == visible.length) {
      _selectedIds.value = <String>{};
    } else {
      _selectedIds.value = visible.map((e) => e.id).toSet();
    }
  }

  void _toggleMultiSelect() {
    _multiSelect.value = !_multiSelect.value;
    _selectedIds.value = <String>{};
  }

  Future<void> _openAddToPlaylistSheet() async {
    final selected = _selectedIds.value;
    if (selected.isEmpty) return;
    final ids = selected.toList(growable: false);
    final added = await showAddToPlaylistDialog(
      context,
      songIds: ids,
    );
    if (!mounted) return;
    if (added == true) {
      _toggleMultiSelect();
    }
  }

  void _togglePlayMode() {
    HapticFeedback.mediumImpact();
    _isSequentialPlay.value = !_isSequentialPlay.value;
    AppToast.show(
      context,
      _isSequentialPlay.value ? '已切换为顺序播放' : '已切换为随机播放',
    );
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
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total > 0 ? done / total : 0,
                      backgroundColor: scheme.onPrimary.withValues(alpha: 0.22),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(scheme.onPrimary),
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

  Map<String, String> _headersFromSong(SongEntity song) {
    final raw = (song.headersJson ?? '').trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
      return const {};
    } catch (_) {
      return const {};
    }
  }

  bool _isMeaningfulTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return false;
    const bad = {
      '未知标题',
      'unknown',
      'unknown title',
      'untitled',
    };
    return !bad.contains(t.toLowerCase());
  }

  bool _isMeaningfulArtist(String artist) {
    final t = artist.trim();
    if (t.isEmpty) return false;
    const bad = {
      '未知艺术家',
      'unknown',
      'unknown artist',
    };
    return !bad.contains(t.toLowerCase());
  }

  Future<bool> _shouldSkipTagProbe(SongEntity song) async {
    final hasBasics = _isMeaningfulTitle(song.title) &&
        _isMeaningfulArtist(song.artist) &&
        (song.album ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasLyrics = await _lyricsRepo.hasCachedLrc(song.id);
    final hasExtras = hasCover || hasLyrics || hasDuration;
    return song.tagsParsed && hasBasics && hasExtras;
  }

  Future<SongEntity?> _scrapeOneSong(SongEntity song) async {
    final uri = (song.uri ?? '').trim();
    if (uri.isEmpty) return null;
    final headers = song.isLocal ? null : _headersFromSong(song);
    final result = song.isLocal
        ? await TagProbeService.instance.probeSong(
            uri: uri,
            isLocal: true,
            includeArtwork: true,
          )
        : await TagProbeService.instance.probeSongDedup(
            uri: uri,
            isLocal: false,
            headers: headers,
            includeArtwork: true,
          );
    if (result == null) return null;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if (artwork != null && artwork.isNotEmpty) {
      final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
        bytes: artwork,
        key: song.id,
      );
      if (cached != null && cached.isNotEmpty) {
        coverPath = cached;
      }
    }

    final lyrics = (result.lyrics ?? '').trim();
    if (lyrics.isNotEmpty) {
      await _lyricsRepo.saveLrcToCache(song.id, lyrics, overwrite: false);
    }

    final nextTitle = (result.title ?? '').trim().isNotEmpty
        ? result.title!.trim()
        : song.title;
    final nextArtist = (result.artist ?? '').trim().isNotEmpty
        ? result.artist!.trim()
        : song.artist;
    final nextAlbum = (result.album ?? '').trim().isNotEmpty
        ? result.album!.trim()
        : song.album;
    final nextDuration = result.durationMs ?? song.durationMs;
    final nextBitrate = result.bitrate ?? song.bitrate;
    final nextSampleRate = result.sampleRate ?? song.sampleRate;
    final nextFileSize = result.fileSize ?? song.fileSize;
    final nextFormat = result.format ?? song.format;

    final updated = SongEntity(
      id: song.id,
      title: nextTitle,
      artist: nextArtist,
      album: nextAlbum,
      uri: song.uri,
      isLocal: song.isLocal,
      headersJson: song.headersJson,
      durationMs: nextDuration,
      bitrate: nextBitrate,
      sampleRate: nextSampleRate,
      fileSize: nextFileSize,
      format: nextFormat,
      sourceId: song.sourceId,
      fileModifiedMs: song.fileModifiedMs,
      localCoverPath: coverPath,
      tagsParsed: true,
    );

    final hasChanges = updated.title != song.title ||
        updated.artist != song.artist ||
        updated.album != song.album ||
        updated.durationMs != song.durationMs ||
        updated.bitrate != song.bitrate ||
        updated.sampleRate != song.sampleRate ||
        updated.fileSize != song.fileSize ||
        updated.format != song.format ||
        updated.localCoverPath != song.localCoverPath ||
        updated.tagsParsed != song.tagsParsed;
    if (!hasChanges) return updated;
    return updated;
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

    final toScrape = <SongEntity>[];
    for (final song in candidates) {
      if (!mounted) return;
      final skip = await _shouldSkipTagProbe(song);
      if (!skip) toScrape.add(song);
    }
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

    var nextIndex = 0;
    final workerCount = toScrape.length < 4 ? toScrape.length : 4;

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex;
        if (idx >= toScrape.length) return;
        nextIndex++;
        final song = toScrape[idx];
        SongEntity? updated;
        try {
          updated = await _scrapeOneSong(song);
        } catch (_) {
          updated = null;
        }
        if (!mounted) return;
        if (updated != null) {
          await _songDao.upsertSongs([updated]);
          _applySongUpdate(updated);
          _scrapeSuccess.value = _scrapeSuccess.value + 1;
        }
        _scrapeDone.value = _scrapeDone.value + 1;
        _updateScrapeOverlay();
      }
    }

    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);

    if (!mounted) return;
    _isScraping.value = false;
    _updateScrapeOverlay();
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _removeScrapeOverlay();
  }

  Future<Uint8List?> _loadArtwork(SongEntity song) {
    final id = song.id;
    final cached = _artworkCache[id];
    if (cached != null) {
      _rememberArtwork(id, cached);
      return Future.value(cached);
    }
    final inflight = _artworkLoading[id];
    if (inflight != null) return inflight;
    final completer = Completer<Uint8List?>();
    _artworkLoading[id] = completer.future;
    _artworkQueue.add(_ArtworkTask(song, completer));
    _drainArtworkQueue();
    return completer.future.whenComplete(() => _artworkLoading.remove(id));
  }

  void _drainArtworkQueue() {
    while (_artworkActive < _artworkMaxConcurrent &&
        _artworkQueue.isNotEmpty) {
      // Use LIFO strategy
      final task = _artworkQueue.removeLast();
      _artworkActive += 1;
      _loadArtworkInternal(task.song)
          .then((bytes) {
            if (!task.completer.isCompleted) {
              task.completer.complete(bytes);
            }
          })
          .catchError((_) {
            if (!task.completer.isCompleted) {
              task.completer.complete(null);
            }
          })
          .whenComplete(() {
            _artworkActive -= 1;
            _drainArtworkQueue();
          });
    }
  }

  Future<Uint8List?> _loadArtworkInternal(SongEntity song) async {
    final cachedPath = song.localCoverPath;
    if (cachedPath != null && cachedPath.isNotEmpty) {
      final file = File(cachedPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _rememberArtwork(song.id, bytes);
          return bytes;
        }
      }
    }
    if (!song.isLocal) return null;
    final uri = song.uri;
    if (uri == null || uri.isEmpty) return null;
    try {
      final original = await _readArtworkBytes(uri);
      if (original == null || original.isEmpty) return null;
      var bytes = original;

      try {
        final compressed = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 144,
          minHeight: 144,
          quality: 80,
        );
        if (compressed.isNotEmpty) {
          bytes = compressed;
        }
      } catch (_) {
      }

      if (_cacheArtworkEnabled &&
          (song.localCoverPath ?? '').trim().isEmpty) {
        final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
          bytes: bytes,
          key: '${song.id}_${song.fileModifiedMs ?? 0}',
        );
        if (cached != null && cached.isNotEmpty) {
          final updated = song.copyWith(localCoverPath: cached);
          unawaited(_songDao.upsertSongs([updated]));
          _applySongUpdate(updated);
        }
      }
      _rememberArtwork(song.id, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _rememberArtwork(String id, Uint8List bytes) {
    _artworkCache.remove(id);
    _artworkCache[id] = bytes;
    while (_artworkCache.length > _artworkCacheMax) {
      final oldestKey = _artworkCache.keys.first;
      _artworkCache.remove(oldestKey);
    }
  }

  void _prefetchArtworkRange(List<SongEntity> songs, int start, int end) {
    if (songs.isEmpty) return;
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end >= songs.length ? songs.length - 1 : end;
    if (safeEnd < safeStart) return;
    for (var i = safeStart; i <= safeEnd; i++) {
      _loadArtwork(songs[i]);
    }
  }

  void _scheduleRangePrefetch(int start, int end, List<SongEntity> songs) {
    if (songs.isEmpty) return;
    final key =
        '${_sourceFilter.value}|${_sortKey.value}|${_ascending.value}|$start|$end|${songs.length}';
    if (key == _lastPrefetchKey && songs.length == _lastPrefetchCount) return;
    _lastPrefetchKey = key;
    _lastPrefetchCount = songs.length;
    Future.microtask(() => _prefetchArtworkRange(songs, start, end));
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
        final webdavIds = _songs.value
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
                    trailing:
                        isSelected ? const Icon(Icons.check_rounded) : null,
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
      builder: (context) {
        return SortSheet(
          options: const [
            SortOption(key: 'title', label: '歌曲名称', icon: Icons.sort_by_alpha),
            SortOption(key: 'artist', label: '歌手名称', icon: Icons.person_outline),
            SortOption(key: 'album', label: '专辑名称', icon: Icons.album_outlined),
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
    final removedSongs =
        _songs.value.where((s) => ids.contains(s.id)).toList(growable: false);
    _isRemoving = true;
    _removeNotifier.value = _RemoveProgress(
      processed: 0,
      total: removedSongs.length,
      isRemoving: true,
    );
    _showRemoveDialog();
    var processed = 0;
    var removedCount = 0;
    for (final song in removedSongs) {
      if (!mounted) break;
      removedCount += await _songDao.deleteByIds([song.id]);
      if (!mounted) break;
      await PlayerService.instance.removeSongsById([song.id]);
      if (!mounted) break;
      await _cleanupCachesForSongs([song]);
      if (!mounted) break;
      final nextSongs = _songs.value.where((s) => s.id != song.id).toList();
      _songs.value = nextSongs;
      _cachedSongs = nextSongs;
      _visibleSongs.value =
          _visibleSongs.value.where((s) => s.id != song.id).toList();
      _visibleSongsAll.value =
          _visibleSongsAll.value.where((s) => s.id != song.id).toList();
      final currentId = _currentId.value;
      if (currentId != null && currentId == song.id) {
        _currentId.value = null;
      }
      final nextSelected = Set<String>.from(_selectedIds.value)
        ..remove(song.id);
      _selectedIds.value = nextSelected;
      processed += 1;
      _removeNotifier.value = _RemoveProgress(
        processed: processed,
        total: removedSongs.length,
        isRemoving: true,
      );
    }
    if (!mounted) return;
    _cachedVisibleAll = null;
    _cachedVisibleSongsRef = null;
    _cachedVisibleKey = null;
    _isRemoving = false;
    _removeNotifier.value = _RemoveProgress(
      processed: processed,
      total: removedSongs.length,
      isRemoving: false,
    );
    AppToast.show(context, '已移除 $removedCount 首');
    _selectedIds.value = <String>{};
    _multiSelect.value = false;
    unawaited(_updateVisibleSongs());
  }

  Future<void> _cleanupCachesForSongs(List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    for (final song in songs) {
      _artworkCache.remove(song.id);
      _artworkLoading.remove(song.id);
      _artworkQueue.removeWhere((t) => t.song.id == song.id);
      await _lyricsRepo.removeCachedLrc(song.id);

      final coverPath = (song.localCoverPath ?? '').trim();
      if (coverPath.isNotEmpty) {
        await ArtworkCacheHelper.removeCachedArtworkByPath(coverPath);
      }
      await ArtworkCacheHelper.removeCachedArtwork(key: song.id);

      final uri = (song.uri ?? '').trim();
      if (song.isLocal || uri.isEmpty || !uri.startsWith('http')) continue;
      final headers = _headersFromSong(song);
      await _audioCache.removeCachedFiles(
        uri: uri,
        headers: headers.isEmpty ? null : headers,
      );
      await TagProbeService.instance.removeRemoteProbeCache(
        uri: uri,
        headers: headers.isEmpty ? null : headers,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        if (_isLoading.value) {
          return AppPageScaffold(
            key: _scaffoldKey,
            extendBodyBehindAppBar: true,
            showMiniPlayer: !_multiSelect.value,
            appBar: AppTopBar(
              title: '歌曲',
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
        final selectedCount = _selectedIds.value.length;
        final isAllSelected = totalCount > 0 && selectedCount == totalCount;

        return AppPageScaffold(
          key: _scaffoldKey,
          extendBodyBehindAppBar: true,
          showMiniPlayer: !_multiSelect.value,
          appBar: AppTopBar(
            title: '歌曲',
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
          body: Column(
            children: [
              MediaListHeader(
                multiSelect: _multiSelect.value,
                isAllSelected: isAllSelected,
                selectedCount: selectedCount,
                totalCount: totalCount,
                isSequentialPlay: _isSequentialPlay.value,
                onToggleSelectAll: () =>
                    _toggleSelectAll(_visibleSongsAll.value),
                onPlay: () {
                  if (_visibleSongsAll.value.isEmpty) return;
                  final queue = List<SongEntity>.from(_visibleSongsAll.value);
                  if (!_isSequentialPlay.value) {
                    queue.shuffle();
                  }
                  _openPlayerWithQueue(queue, 0);
                },
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
                        bottomInset: MediaQuery.of(context).padding.bottom +
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
                                final next = Set<String>.from(selected);
                                if (next.contains(song.id)) {
                                  next.remove(song.id);
                                } else {
                                  next.add(song.id);
                                }
                                _selectedIds.value = next;
                              } else {
                                _currentId.value = song.id;
                                final queue =
                                    List<SongEntity>.from(_visibleSongsAll.value);
                                if (!_isSequentialPlay.value) {
                                  queue.shuffle();
                                }
                                final startIndex =
                                    queue.indexWhere((s) => s.id == song.id);
                                _openPlayerWithQueue(
                                  queue,
                                  startIndex == -1 ? 0 : startIndex,
                                );
                              }
                            },
                            onLongPress: () {
                              if (_multiSelect.value) {
                                final next = Set<String>.from(selected);
                                if (next.contains(song.id)) {
                                  next.remove(song.id);
                                } else {
                                  next.add(song.id);
                                }
                                _selectedIds.value = next;
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
                                        MaterialPageRoute(
                                          builder: (_) => ArtistDetailPage(
                                            artistName: artistName,
                                          ),
                                        ),
                                      );
                                    },
                                    onOpenAlbum: (albumName) {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AlbumDetailPage(
                                            albumName: albumName,
                                          ),
                                        ),
                                      );
                                    },
                                    onUpdated: (updated) {
                                      if (!mounted) return;
                                      final updatedSongs = _songs.value
                                          .map((s) =>
                                              s.id == updated.id ? updated : s)
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
                                          () => _cleanupCachesForSongs(
                                            [deleted!],
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
                                  final index = visibleSongs
                                      .indexWhere((s) => s.id == targetId);
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
                MultiSelectBottomBar(
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
            ],
          ),
        );
      },
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
                  (widget.size * MediaQuery.of(context).devicePixelRatio).toInt(),
              cacheHeight:
                  (widget.size * MediaQuery.of(context).devicePixelRatio).toInt(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _ArtworkPlaceholder(song: widget.song, size: widget.size);
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
                  (widget.size * MediaQuery.of(context).devicePixelRatio).toInt(),
              cacheHeight:
                  (widget.size * MediaQuery.of(context).devicePixelRatio).toInt(),
              fit: BoxFit.cover,
            ),
          );
        }
        return _ArtworkPlaceholder(song: widget.song, size: widget.size);
      },
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  final SongEntity song;
  final double size;

  const _ArtworkPlaceholder({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
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

Future<Uint8List?> _readArtworkBytes(String uri) async {
  try {
    final file = File(uri);
    if (!await file.exists()) return null;
    final metadata = readMetadata(file, getImage: true);
    if (metadata.pictures.isEmpty) return null;
    final bytes = metadata.pictures.first.bytes;
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<List<SongEntity>> _buildVisibleSongsAsync({
  required List<SongEntity> songs,
  required String sourceFilter,
  required String sortKey,
  required bool ascending,
}) async {
  final payload = <String, dynamic>{
    'songs': songs.map((e) => e.toMap()).toList(),
    'sourceFilter': sourceFilter,
    'sortKey': sortKey,
    'ascending': ascending,
  };
  final result = await compute(_buildVisibleSongsIsolate, payload);
  return result
      .map((e) => SongEntity.fromMap((e as Map).cast<String, dynamic>()))
      .toList();
}

List<Map<String, dynamic>> _buildVisibleSongsIsolate(
  Map<String, dynamic> args,
) {
  final sourceFilter = (args['sourceFilter'] as String?) ?? 'all';
  final sortKey = (args['sortKey'] as String?) ?? 'title';
  final ascending = (args['ascending'] as bool?) ?? true;
  final rawSongs = (args['songs'] as List).cast<Map>();
  final songs = rawSongs
      .map((e) => SongEntity.fromMap(e.cast<String, dynamic>()))
      .toList();

  List<SongEntity> list;
  if (sourceFilter == 'local') {
    list = songs.where((song) => song.sourceId == 'local').toList();
  } else if (sourceFilter == 'webdav') {
    list = songs.where((song) => song.sourceId != 'local').toList();
  } else if (sourceFilter.startsWith('webdav:')) {
    final id = sourceFilter.substring('webdav:'.length);
    list = songs.where((song) => song.sourceId == id).toList();
  } else {
    list = List<SongEntity>.from(songs);
  }

  final pinyinCache = <String, String>{};
  String sortKeyStr(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return '';
    final cached = pinyinCache[trimmed];
    if (cached != null) return cached;
    final p = PinyinHelper.getPinyin(
      trimmed,
      separator: '',
      format: PinyinFormat.WITHOUT_TONE,
    );
    final key = (p.isNotEmpty ? p : trimmed).toLowerCase();
    pinyinCache[trimmed] = key;
    return key;
  }

  bool isUnknownTitle(SongEntity s) => s.title.trim().isEmpty || s.title == '未知标题';
  bool isUnknownArtist(SongEntity s) =>
      s.artist.trim().isEmpty || s.artist == '未知艺术家';
  bool isUnknownAlbum(SongEntity s) {
    final a = (s.album ?? '').trim();
    return a.isEmpty || a == '未知专辑';
  }

  int compare(SongEntity a, SongEntity b) {
    int result;
    switch (sortKey) {
      case 'artist':
        result = sortKeyStr(isUnknownArtist(a) ? '' : a.artist)
            .compareTo(sortKeyStr(isUnknownArtist(b) ? '' : b.artist));
        break;
      case 'album':
        result = sortKeyStr(isUnknownAlbum(a) ? '' : (a.album ?? ''))
            .compareTo(sortKeyStr(isUnknownAlbum(b) ? '' : (b.album ?? '')));
        break;
      case 'duration':
        result = (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
        break;
      case 'title':
      default:
        result = sortKeyStr(isUnknownTitle(a) ? '' : a.title)
            .compareTo(sortKeyStr(isUnknownTitle(b) ? '' : b.title));
    }
    return ascending ? result : -result;
  }

  list.sort(compare);

  if (sortKey == 'artist') {
    final unknown = list.where(isUnknownArtist).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownArtist);
      list.insertAll(0, unknown);
    }
  } else if (sortKey == 'album') {
    final unknown = list.where(isUnknownAlbum).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownAlbum);
      list.insertAll(0, unknown);
    }
  } else if (sortKey == 'title') {
    final unknown = list.where(isUnknownTitle).toList();
    if (unknown.isNotEmpty) {
      list.removeWhere(isUnknownTitle);
      list.insertAll(0, unknown);
    }
  }

  return list.map((e) => e.toMap()).toList();
}
