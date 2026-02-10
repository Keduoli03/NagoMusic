import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:signals/signals.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../core/database/database_helper.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../models/music_entity.dart';
import '../models/playlist_model.dart';
import '../utils/remote_metadata_helper.dart';

enum SongFilter { all, local, webdav }

class _MetadataTask {
  _MetadataTask(this.base, this.path, this.completer);
  final MusicEntity base;
  final String path;
  final Completer<MusicEntity> completer;
}

class LibraryViewModel {
  static final LibraryViewModel _instance = LibraryViewModel._internal();
  factory LibraryViewModel() => _instance;
  LibraryViewModel._internal() {
    _filter = _loadFilter();
    _homeFilter = _loadHomeFilter();
    _showPlaylistCovers = StorageUtil.getBoolOrDefault(StorageKeys.showPlaylistCovers, defaultValue: false);
    _blockedArtists = StorageUtil.getStringListOrDefault(StorageKeys.blockedArtists);
    _blockedAlbums = StorageUtil.getStringListOrDefault(StorageKeys.blockedAlbums);
    Future.microtask(() async {
      await _loadSources();
      await _loadCachedSongs();
      await _loadPlaylists();
    });
  }
  static const String _localSourceId = 'local';
  static const String _webDavSourceId = 'webdav';

  List<MusicEntity> _allSongs = [];
  List<MusicSource> _sources = [];
  List<Playlist> _playlists = [];
  bool _isLoading = false;
  bool _isSourcesLoaded = false;
  
  // Global UI State
  final isMenuOpen = signal(false);
  final isGlobalMultiSelectModeSignal = signal(false);

  // Getter for UI consumption
  bool get isGlobalMultiSelectMode => isGlobalMultiSelectModeSignal.value;

  // Setter/Method for state updates
  void setGlobalMultiSelectMode(bool value) {
    if (isGlobalMultiSelectModeSignal.value != value) {
      isGlobalMultiSelectModeSignal.value = value;
      // Bump settingsTick if listeners depend on it for this change
      _bump(settingsTick);
    }
  }

  int _scanProcessed = 0;
  int _scanAdded = 0;
  DateTime _lastScanNotify = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMetadataNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _searchMetadataRunning = false;
  DateTime _lastSearchMetadataTrigger = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSearchMetadataQuery = '';
  String _sortKey = 'title';
  bool _ascending = true;
  SongFilter _filter = SongFilter.all;
  SongFilter _homeFilter = SongFilter.all;
  bool _showPlaylistCovers = false;
  List<String> _blockedArtists = [];
  List<String> _blockedAlbums = [];
  bool _cancelScanSignal = false;

  final Signal<int> libraryTick = signal(0);
  final Signal<int> scanTick = signal(0);
  final Signal<int> settingsTick = signal(0);

  void cancelScan() {
    _cancelScanSignal = true;
  }

  void _bump(Signal<int> tick) {
    tick.value++;
  }

  List<MusicEntity> get songs {
    final filtered = _allSongs.where((s) {
      if (_filter == SongFilter.local) return s.isLocal;
      if (_filter == SongFilter.webdav) return !s.isLocal;
      return true;
    }).toList();
    return filtered;
  }
  
  bool get showPlaylistCovers => _showPlaylistCovers;

  void setShowPlaylistCovers(bool value) {
    if (_showPlaylistCovers != value) {
      _showPlaylistCovers = value;
      StorageUtil.setBool(StorageKeys.showPlaylistCovers, value);
      _bump(settingsTick);
    }
  }

  List<MusicEntity> get homeSongs {
    final filtered = _allSongs.where((s) {
      if (_homeFilter == SongFilter.local) return s.isLocal;
      if (_homeFilter == SongFilter.webdav) return !s.isLocal;
      return true;
    }).toList();
    return filtered;
  }

  List<MusicEntity> get allSongs => List.unmodifiable(_allSongs);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<String> get blockedArtists => List.unmodifiable(_blockedArtists);
  List<String> get blockedAlbums => List.unmodifiable(_blockedAlbums);
  
  List<MusicSource> get sources => List.unmodifiable(_sources);
  bool get isLoading => _isLoading;
  int get scanProcessedCount => _scanProcessed;
  int get scanAddedCount => _scanAdded;
  String get sortKey => _sortKey;
  bool get ascending => _ascending;
  SongFilter get filter => _filter;
  SongFilter get homeFilter => _homeFilter;

  void setFilter(SongFilter f) {
    if (_filter != f) {
      _filter = f;
      StorageUtil.setString(StorageKeys.songsFilter, _filter.name);
      _bump(settingsTick);
    }
  }

  void setHomeFilter(SongFilter f) {
    if (_homeFilter != f) {
      _homeFilter = f;
      StorageUtil.setString(StorageKeys.homeSongsFilter, _homeFilter.name);
      _bump(settingsTick);
    }
  }

  Future<void> blockArtist(String name) async {
    if (!_blockedArtists.contains(name)) {
      _blockedArtists = [..._blockedArtists, name];
      await StorageUtil.setStringList(StorageKeys.blockedArtists, _blockedArtists);
      _bump(settingsTick);
    }
  }

  Future<void> unblockArtist(String name) async {
    if (_blockedArtists.contains(name)) {
      _blockedArtists = List.from(_blockedArtists)..remove(name);
      await StorageUtil.setStringList(StorageKeys.blockedArtists, _blockedArtists);
      _bump(settingsTick);
    }
  }

  Future<void> blockAlbum(String name) async {
    if (!_blockedAlbums.contains(name)) {
      _blockedAlbums = [..._blockedAlbums, name];
      await StorageUtil.setStringList(StorageKeys.blockedAlbums, _blockedAlbums);
      _bump(settingsTick);
    }
  }

  Future<void> unblockAlbum(String name) async {
    if (_blockedAlbums.contains(name)) {
      _blockedAlbums = List.from(_blockedAlbums)..remove(name);
      await StorageUtil.setStringList(StorageKeys.blockedAlbums, _blockedAlbums);
      _bump(settingsTick);
    }
  }

  SongFilter _loadFilter() {
    final raw = StorageUtil.getStringOrDefault(
      StorageKeys.songsFilter,
      defaultValue: SongFilter.all.name,
    );
    return _parseFilter(raw);
  }

  SongFilter _loadHomeFilter() {
    final raw = StorageUtil.getStringOrDefault(
      StorageKeys.homeSongsFilter,
      defaultValue: SongFilter.all.name,
    );
    return _parseFilter(raw);
  }

  SongFilter _parseFilter(String raw) {
    switch (raw) {
      case 'local':
        return SongFilter.local;
      case 'webdav':
        return SongFilter.webdav;
      default:
        return SongFilter.all;
    }
  }

  Future<void> _loadPlaylists() async {
    _playlists = await DatabaseHelper().getPlaylists();
    _bump(libraryTick);
  }

  Future<int> createPlaylist(String name) async {
    final id = await DatabaseHelper().createPlaylist(name);
    await _loadPlaylists();
    return id;
  }

  Future<void> deletePlaylist(int id) async {
    await DatabaseHelper().deletePlaylist(id);
    await _loadPlaylists();
  }

  Future<void> addSongToPlaylist(int playlistId, String songId) async {
    await DatabaseHelper().addSongToPlaylist(playlistId, songId);
  }

  Future<void> addSongsToPlaylist(int playlistId, List<String> songIds) async {
    await DatabaseHelper().addSongsToPlaylist(playlistId, songIds);
  }

  Future<void> removeSongFromPlaylist(int playlistId, String songId) async {
    await DatabaseHelper().removeSongFromPlaylist(playlistId, songId);
  }

  Future<void> reorderPlaylist(int playlistId, List<String> orderedSongIds) async {
    await DatabaseHelper().updatePlaylistSongOrder(playlistId, orderedSongIds);
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    await DatabaseHelper().renamePlaylist(playlistId, newName);
    await _loadPlaylists();
  }

  Future<void> reorderPlaylists(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _playlists.removeAt(oldIndex);
    _playlists.insert(newIndex, item);
    _bump(libraryTick);
    
    // Update DB
    final ids = _playlists.map((p) => p.id).toList();
    await DatabaseHelper().updatePlaylistOrder(ids);
  }

  Future<void> movePlaylistToTop(int playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;

    // Check if first playlist is system/favorite
    // We want to move below the favorite playlist if it exists
    int targetIndex = 0;
    if (_playlists.isNotEmpty && _playlists[0].isFavorite) {
      if (_playlists[0].id == playlistId) return; // Cannot move favorite playlist
      targetIndex = 1;
    }

    if (index == targetIndex) return;

    await reorderPlaylists(index, targetIndex);
  }

  Future<List<MusicEntity>> getSongsInPlaylist(int playlistId) async {
    final songIds = await DatabaseHelper().getSongIdsInPlaylist(playlistId);
    if (songIds.isEmpty) return [];
    
    // We need to fetch full song details.
    // Optimization: filtering from memory if all songs are loaded is faster than DB query
    // But DB query is safer if memory is partial. 
    // Since _allSongs should contain all available songs, let's try to find them there first.
    // However, _allSongs might be large.
    
    final dbSongs = await DatabaseHelper().getSongsByIds(songIds);
    // Preserve order from playlist_songs (which is by added_at DESC)
    // The DatabaseHelper.getSongsByIds might not preserve order if it uses IN clause.
    // So we need to reorder them.
    
    final songMap = {for (var s in dbSongs) s.id: s};
    final result = <MusicEntity>[];
    for (var id in songIds) {
      if (songMap.containsKey(id)) {
        result.add(songMap[id]!);
      }
    }
    return result;
  }
MusicSource getOrCreateLocalSource() {
    if (!_isSourcesLoaded) {
      return const MusicSource(
        id: _localSourceId,
        type: MusicSourceType.local,
        name: '本地音乐',
      );
    }
    final existing = _findSourceById(_localSourceId);
    if (existing != null) {
      return existing;
    }
    final source = const MusicSource(
      id: _localSourceId,
      type: MusicSourceType.local,
      name: '本地音乐',
    );
    _sources = [..._sources, source];
    _saveSources();
    return source;
  }

  MusicSource getOrCreateWebDavSource() {
    if (!_isSourcesLoaded) {
      return const MusicSource(
        id: _webDavSourceId,
        type: MusicSourceType.webdav,
        name: 'WebDAV',
      );
    }
    final existing = _findSourceById(_webDavSourceId);
    if (existing != null) {
      return existing;
    }
    final source = const MusicSource(
      id: _webDavSourceId,
      type: MusicSourceType.webdav,
      name: 'WebDAV',
    );
    _sources = [..._sources, source];
    _saveSources();
    return source;
  }

  MusicSource createWebDavDraft({String? name}) {
    final n = (name ?? '').trim();
    return MusicSource(
      id: _newWebDavId(),
      type: MusicSourceType.webdav,
      name: n.isEmpty ? 'WebDAV' : n,
    );
  }

  String _newWebDavId() {
    return 'webdav_${DateTime.now().microsecondsSinceEpoch}';
  }

  MusicSource? _findSourceById(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> upsertSource(MusicSource source) async {
    final index = _sources.indexWhere((e) => e.id == source.id);
    if (index >= 0) {
      _sources = [..._sources]..[index] = source;
    } else {
      _sources = [..._sources, source];
    }
    await _saveSources();
    _bump(libraryTick);
  }

  Future<void> removeSource(MusicSource source) async {
    if (source.id == _localSourceId) return;
    final nextSources = _sources.where((s) => s.id != source.id).toList();
    if (nextSources.length == _sources.length) return;
    _sources = nextSources;
    await _saveSources();
    final dbHelper = DatabaseHelper();
    await dbHelper.clearSongsBySource(source.id);
    await _loadCachedSongs();
    _bump(libraryTick);
  }

  Future<List<FolderInfo>> getFolders() async {
    final source = getOrCreateLocalSource();
    final List<FolderInfo> results = [];
    final localSongs = songs.where((s) => s.isLocal && s.uri != null).toList();

    int countByPath(String path, {List<String> excludePaths = const []}) {
      final normalizedPath = path.replaceAll('\\', '/');
      final prefix = normalizedPath.endsWith('/') ? normalizedPath : '$normalizedPath/';

      final excludePrefixes = excludePaths.map((p) {
        final np = p.replaceAll('\\', '/');
        return np.endsWith('/') ? np : '$np/';
      }).toList();

      return localSongs.where((s) {
        final uri = s.uri;
        if (uri == null || uri.isEmpty) return false;
        
        // Filter by duration if configured
        if (source.minDurationMs != null && source.minDurationMs! > 0) {
          final duration = s.durationMs ?? 0;
          if (duration < source.minDurationMs!) {
            return false;
          }
        }

        final songPath = uri.replaceAll('\\', '/');
        
        // Must be in current path
        if (songPath != normalizedPath && !songPath.startsWith(prefix)) {
          return false;
        }

        // Must NOT be in any exclude path
        for (final ex in excludePrefixes) {
          if (songPath.startsWith(ex)) return false;
        }

        return true;
      }).length;
    }

    // 1. System Folders
    if (source.useSystemLibrary) {
      final paths = await loadLocalFolders();
      for (final p in paths) {
        final count = await p.assetCountAsync;
        if (count > 0) {
          results.add(FolderInfo(
            id: p.id,
            name: p.name,
            count: count,
            isSystem: true,
            entity: p,
          ),);
        }
      }
    }

    // 2. Custom Folders (Aggregated from songs)
    // Only if system library is OFF, or to supplement?
    // If system library is ON, PhotoManager usually covers everything on device.
    // But if user added a specific folder that PhotoManager missed (unlikely but possible),
    // or if we want to show structure.
    // For now, to solve the user's issue: "Local Management did not show folders" when system lib is OFF.
    // So we definitely need this when useSystemLibrary is false.
    if (!source.useSystemLibrary) {
      final includeSet = source.includeFolders.toSet();
      for (final path in includeSet) {
        if (path.trim().isEmpty) continue;

        final subFolders = includeSet.where((other) {
          if (other == path) return false;
          return p.isWithin(path, other);
        }).toList();

        final count = countByPath(path, excludePaths: subFolders);
        if (count > 0) {
          results.add(
            FolderInfo(
              id: path,
              name: p.basename(path),
              count: count,
              isSystem: false,
            ),
          );
        }
      }
    }

    // Deduplicate?
    // If system lib is ON, we only show system folders to avoid confusion.
    // Or we can merge.
    // For now, if useSystemLibrary is true, we mostly rely on it.
    // But if useSystemLibrary is false, we rely on Custom Folders.
    
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  Future<List<AssetPathEntity>> loadLocalFolders() async {
    final source = getOrCreateLocalSource();
    if (!source.useSystemLibrary) {
      return [];
    }

    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.audio,
          mediaLocation: false,
        ),
      ),
    );
    if (!ps.isAuth) {
      PhotoManager.openSetting();
      return [];
    }
    
    final filterOption = FilterOptionGroup(
      orders: [
        const OrderOption(type: OrderOptionType.updateDate, asc: false),
      ],
    );

    // Apply duration filter if configured
    if (source.minDurationMs != null && source.minDurationMs! > 0) {
      filterOption.setOption(
        AssetType.audio,
        FilterOption(
          durationConstraint: DurationConstraint(
            min: Duration(milliseconds: source.minDurationMs!),
          ),
        ),
      );
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.audio,
      filterOption: filterOption,
    );
    return paths.where((p) => !p.isAll && p.name != 'Recent' && p.name != 'Recent added').toList();
  }

  Future<void> scanLocalMusic() async {
    final source = getOrCreateLocalSource();
    await scanSource(source);
  }

  Future<int> scanSource(MusicSource source, {bool notifyLoading = true}) async {
    _resetScanProgress();
    _cancelScanSignal = false;
    if (notifyLoading) {
      _isLoading = true;
      _bump(scanTick);
    }
    var added = 0;
    try {
      if (source.type == MusicSourceType.local) {
        added = await _scanLocalSource(source);
      } else {
        added = await _scanWebDavSource(source);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('scanSource error: $e');
      }
    } finally {
      if (notifyLoading) {
        _isLoading = false;
        _bump(scanTick);
      }
    }
    return added;
  }

  Future<void> deleteSongs(List<String> ids) async {
    if (ids.isEmpty) return;
    await DatabaseHelper().deleteSongsByIds(ids);
    _allSongs.removeWhere((s) => ids.contains(s.id));
    _bump(libraryTick);
    _bump(scanTick);
  }

  Future<List<WebDavEntry>> listWebDavContents(
    MusicSource source, {
    String? path,
  }) async {
    return _listWebDavEntries(source, path: path);
  }

  Future<bool> testWebDavConnection(MusicSource source) async {
    final endpoint = source.endpoint?.trim() ?? '';
    if (endpoint.isEmpty) return false;
    final client = webdav.newClient(
      endpoint,
      user: '',
      password: '',
      debug: kDebugMode,
    );

    final username = source.username?.trim() ?? '';
    final password = source.password ?? '';
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Content-Type': 'text/xml',
    };
    if (username.isNotEmpty || password.isNotEmpty) {
      final auth = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $auth';
    }
    client.setHeaders(headers);

    try {
      await client.readDir('/');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> listWebDavFolders(MusicSource source) async {
    final entries = await _listWebDavEntries(source, path: source.path);
    return entries.where((e) => e.isCollection).map((e) => e.href).toList();
  }

  Future<int> _scanLocalSource(MusicSource source) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.audio,
          mediaLocation: false,
        ),
      ),
    );
    if (!ps.isAuth) {
      PhotoManager.openSetting();
      return 0;
    }

    // Definitions
    final include = source.includeFolders.toSet();
    final exclude = source.excludeFolders.toSet();
    final List<MusicEntity> newSongs = [];
    final Set<String> seenIds = {};
    final existingById = <String, MusicEntity>{};
    var addedCount = 0;
    var processed = 0;
    final Queue<_MetadataTask> metadataQueue = Queue<_MetadataTask>();
    final metadataWorkers = <Future<void>>[];
    var metadataScanDone = false;
    final storedConcurrency = StorageUtil.getIntOrDefault(
      StorageKeys.localMetadataConcurrency,
      defaultValue: 6,
    );
    final metadataConcurrency =
        storedConcurrency < 1 ? 1 : storedConcurrency;
    final List<Future<MusicEntity>> pendingSongs = [];

    Future<void> metadataWorker() async {
      while (true) {
        if (_cancelScanSignal) break;
        if (metadataQueue.isEmpty) {
          if (metadataScanDone) break;
          await Future.delayed(const Duration(milliseconds: 10));
          continue;
        }
        final task = metadataQueue.removeFirst();
        final base = task.base;
        final uri = base.uri;
        if (uri == null || uri.isEmpty) {
          task.completer.complete(base);
          continue;
        }
        final file = File(uri);
        if (!await file.exists()) {
          task.completer.complete(base);
          continue;
        }
        try {
          final metadata = readMetadata(file, getImage: false);
          final title = metadata.title?.trim();
          final artist = metadata.artist?.trim();
          final album = metadata.album?.trim();
          final rawLyrics = metadata.lyrics;
          String? normalizedLyrics;
          if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
            normalizedLyrics = rawLyrics.replaceFirst(RegExp('^\uFEFF'), '').trim();
          }
          final updated = base.copyWith(
            title: title?.isNotEmpty == true ? title! : base.title,
            artist: artist?.isNotEmpty == true ? artist! : base.artist,
            album: album?.isNotEmpty == true ? album : base.album,
            lyrics: normalizedLyrics ?? base.lyrics,
            fileModifiedMs: base.fileModifiedMs,
            fileSize: file.lengthSync(),
            bitrate: metadata.bitrate,
            sampleRate: metadata.sampleRate,
            format: p.extension(file.path).replaceAll('.', '').toUpperCase(),
          );
          task.completer.complete(updated);
        } catch (_) {
          task.completer.complete(base);
        }
      }
    }

    Future<MusicEntity> enqueueMetadata(MusicEntity song, String path) {
      if (!_needsLocalInfoSync(song, path)) {
        return Future.value(song);
      }
      final completer = Completer<MusicEntity>();
      metadataQueue.add(_MetadataTask(song, path, completer));
      return completer.future;
    }

    for (var i = 0; i < metadataConcurrency; i++) {
      metadataWorkers.add(metadataWorker());
    }

    // 0. Guard: If no system library and no custom folders, clear and return
    if (!source.useSystemLibrary && source.includeFolders.isEmpty) {
      await _replaceSongsForSource(source.id, []);
      return 0;
    }

      for (final song in _allSongs) {
      if (song.sourceId == source.id) {
        existingById[song.id] = song;
      }
    }

    // 1. Scan based on mode (Union Strategy)
    // If useSystemLibrary is true, scan system folders.
    // If includeFolders is not empty, ALSO scan custom folders.
    
    if (source.useSystemLibrary) {
      // System Mode: Scan PhotoManager folders
      final List<AssetPathEntity> paths =
          await PhotoManager.getAssetPathList(type: RequestType.audio);
      
      // Filter out Recent/All from PhotoManager results to avoid redundancy
      List<AssetPathEntity> filtered = paths.where((p) => !p.isAll && p.name != 'Recent' && p.name != 'Recent added').toList();
      
      // In System Mode, we ignore 'includeFolders' as the user wants auto-scan.
      // But we still respect 'excludeFolders'.
      if (exclude.isNotEmpty) {
        filtered = filtered.where((p) => !exclude.contains(p.id)).toList();
      }

      var remaining = 500; // Limit for PhotoManager scanning
      
      for (final path in filtered) {
        if (remaining <= 0) break;
        final entities = await path.getAssetListRange(
          start: 0,
          end: remaining,
        );
        remaining -= entities.length;
        for (final e in entities) {
          if (source.minDurationMs != null &&
              e.duration * 1000 < source.minDurationMs!) {
            continue;
          }
          final file = await e.file;
          if (file != null) {
            // Check if file path is excluded
            if (exclude.any((ex) => file.path.startsWith(ex))) continue;

            final stat = await file.stat();
            final modifiedMs = stat.modified.millisecondsSinceEpoch;
            final existing = existingById[file.path];
            if (existing != null) {
              if (!seenIds.contains(existing.id)) {
                seenIds.add(existing.id);
                var current = existing;
                // Update duration if missing
                if (current.durationMs == 0 && e.duration > 0) {
                  current = current.copyWith(durationMs: e.duration * 1000);
                }

                if (current.fileModifiedMs == modifiedMs) {
                  final task = enqueueMetadata(current, file.path);
                  pendingSongs.add(task);
                } else {
                  final updated = current.copyWith(fileModifiedMs: modifiedMs);
                  final task = enqueueMetadata(updated, file.path);
                  pendingSongs.add(task);
                }
              }
              processed += 1;
              _bumpScanProgress(processedDelta: 1, addedDelta: 0);
              if (processed % 25 == 0) {
                await Future.delayed(const Duration(milliseconds: 1));
              }
              continue;
            }

            final stub = _buildLocalStub(file, source, modifiedMs, durationMs: e.duration * 1000);
            final added = _appendLocalStub(stub, newSongs, seenIds);
            processed += 1;
            if (added) {
              addedCount += 1;
              final task = enqueueMetadata(stub, file.path);
              pendingSongs.add(task);
            }
            _bumpScanProgress(processedDelta: 1, addedDelta: added ? 1 : 0);
            if (processed % 25 == 0) {
              await Future.delayed(const Duration(milliseconds: 1));
            }
          }
        }
      }
    }

    // Always scan custom folders if present (Union Strategy)
    if (source.includeFolders.isNotEmpty) {
      // Custom Mode: Scan Custom Paths (includeFolders)
      final customPaths = include.toList();

      for (final pathStr in customPaths) {
        final dir = Directory(pathStr);
        if (!await dir.exists()) continue;

        try {
          final files = dir.list(recursive: true, followLinks: false);
          await for (final fsEntity in files) {
            if (fsEntity is File) {
               if (_isAudioFile(fsEntity.path)) {
                 // Check exclusions
                 if (exclude.any((ex) => fsEntity.path.startsWith(ex))) continue;
                 
                 // Check min duration (requires reading file, optimization: skip if possible or check later)
                 // We'll process it and check duration inside _processLocalFile or helper
                 final stat = await fsEntity.stat();
                 final modifiedMs = stat.modified.millisecondsSinceEpoch;
                 final existing = existingById[fsEntity.path];
                 if (existing != null) {
                   if (!seenIds.contains(existing.id)) {
                     seenIds.add(existing.id);
                     if (existing.fileModifiedMs == modifiedMs) {
                      final task = enqueueMetadata(existing, fsEntity.path);
                      pendingSongs.add(task);
                     } else {
                       final updated = existing.copyWith(fileModifiedMs: modifiedMs);
                      final task = enqueueMetadata(updated, fsEntity.path);
                      pendingSongs.add(task);
                     }
                   }
                   processed += 1;
                   _bumpScanProgress(processedDelta: 1, addedDelta: 0);
                   if (processed % 25 == 0) {
                     await Future.delayed(const Duration(milliseconds: 1));
                   }
                   continue;
                 }

                 final stub = _buildLocalStub(fsEntity, source, modifiedMs);
                 final added = _appendLocalStub(stub, newSongs, seenIds);
                 processed += 1;
                 if (added) {
                   addedCount += 1;
                   final task = enqueueMetadata(stub, fsEntity.path);
                   pendingSongs.add(task);
                 }
                 _bumpScanProgress(processedDelta: 1, addedDelta: added ? 1 : 0);
                 if (processed % 25 == 0) {
                   await Future.delayed(const Duration(milliseconds: 1));
                 }
               }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error scanning custom path $pathStr: $e');
        }
      }
    }

    metadataScanDone = true;
    if (metadataWorkers.isNotEmpty) {
      await Future.wait(metadataWorkers);
    }
    if (pendingSongs.isNotEmpty) {
      final resolved = await Future.wait(pendingSongs);
      newSongs
        ..clear()
        ..addAll(resolved);
    }
    await _replaceSongsForSource(source.id, newSongs);
    return addedCount;
  }

  MusicEntity _buildLocalStub(File file, MusicSource source, int modifiedMs, {int durationMs = 0}) {
    return MusicEntity(
      id: file.path,
      title: p.basenameWithoutExtension(file.path),
      artist: '未知艺术家',
      album: null,
      uri: file.path,
      isLocal: true,
      durationMs: durationMs,
      sourceId: source.id,
      localCoverPath: null,
      fileModifiedMs: modifiedMs,
    );
  }

  bool _appendLocalStub(
    MusicEntity stub,
    List<MusicEntity> songs,
    Set<String> seenIds,
  ) {
    if (seenIds.contains(stub.id)) return false;
    seenIds.add(stub.id);
    songs.add(stub);
    return true;
  }

  bool _needsLocalMetadata(MusicEntity song, String path) {
    if (song.fileSize == null) return true;
    final base = p.basenameWithoutExtension(path).trim();
    final title = song.title.trim();
    final artist = song.artist.trim();
    final album = (song.album ?? '').trim();
    final lyrics = (song.lyrics ?? '').trim();
    if (title.isEmpty || title == base) return true;
    if (artist.isEmpty || artist == '未知艺术家') return true;
    if (album.isEmpty) return true;
    if (lyrics.isEmpty) return true;
    return false;
  }

  bool _needsLocalInfoSync(MusicEntity song, String path) {
    return _needsLocalMetadata(song, path);
  }

  void enqueueLocalSearchMetadata(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    if (_searchMetadataRunning) return;
    final now = DateTime.now();
    if (q == _lastSearchMetadataQuery &&
        now.difference(_lastSearchMetadataTrigger).inMilliseconds < 600) {
      return;
    }
    _lastSearchMetadataQuery = q;
    _lastSearchMetadataTrigger = now;
    final targets = <MusicEntity>[];
    for (final song in _allSongs) {
      final uri = song.uri;
      if (!song.isLocal || uri == null || uri.isEmpty) continue;
      if (_needsLocalMetadata(song, uri)) {
        targets.add(song);
      }
    }
    if (targets.isEmpty) return;
    _searchMetadataRunning = true;
    Future(() async {
      await _refreshLocalTextMetadata(targets);
      _searchMetadataRunning = false;
    });
  }

  Future<void> _refreshLocalTextMetadata(List<MusicEntity> targets) async {
    if (targets.isEmpty) return;
    final dbHelper = DatabaseHelper();
    var processed = 0;

    for (final base in targets) {
      final uri = base.uri;
      if (uri == null || uri.isEmpty) continue;
      final file = File(uri);
      if (!await file.exists()) continue;

      try {
        final metadata = readMetadata(file, getImage: false);
        final title = metadata.title?.trim();
        final artist = metadata.artist?.trim();
        final album = metadata.album?.trim();
        final rawLyrics = metadata.lyrics;
        String? normalizedLyrics;
        if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
          normalizedLyrics = rawLyrics.replaceFirst(RegExp('^\uFEFF'), '').trim();
        }
        final updated = base.copyWith(
          title: title?.isNotEmpty == true ? title! : base.title,
          artist: artist?.isNotEmpty == true ? artist! : base.artist,
          album: album?.isNotEmpty == true ? album : base.album,
          lyrics: normalizedLyrics ?? base.lyrics,
          fileModifiedMs: base.fileModifiedMs,
          fileSize: file.lengthSync(),
          bitrate: metadata.bitrate,
          sampleRate: metadata.sampleRate,
          format: p.extension(file.path).replaceAll('.', '').toUpperCase(),
        );

        await dbHelper.insertSong(updated);
        _replaceSongInMemory(updated);
      } catch (_) {}

      processed += 1;
      if (processed % 8 == 0) {
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }
    _bump(libraryTick);
  }

  void _replaceSongInMemory(MusicEntity updated) {
    final index = _allSongs.indexWhere((s) => s.id == updated.id);
    if (index < 0) return;
    _allSongs = [..._allSongs]..[index] = updated;
    _allSongs = _sortSongs(_allSongs);
    final now = DateTime.now();
    if (now.difference(_lastMetadataNotify).inMilliseconds > 300) {
      _lastMetadataNotify = now;
      _bump(libraryTick);
    }
  }

  Future<int> _scanWebDavSource(MusicSource source) async {
    if (source.endpoint == null || source.endpoint!.isEmpty) return 0;
    
    final dbHelper = DatabaseHelper();
    final existingAll = await dbHelper.getSongs();
    final existingById = <String, MusicEntity>{};
    for (final song in existingAll) {
      if (song.sourceId == source.id) {
        existingById[song.id] = song;
      }
    }

    final List<String> pathsToScan = source.includeFolders.isNotEmpty 
        ? source.includeFolders 
        : [source.path ?? '/'];

    final newSongs = <MusicEntity>[];
    final headers = _buildAuthHeaders(source);
    final Set<String> visited = {};

    for (final scanPath in pathsToScan) {
      if (_cancelScanSignal) break;
      await _scanWebDavRecursive(
        source,
        scanPath,
        newSongs,
        headers,
        visited,
        existingById,
      );
    }
    final enrichedSongs = await _scanWebDavMetadata(newSongs, source);
    await _replaceSongsForSource(source.id, enrichedSongs);
    return enrichedSongs.length;
  }

  Future<void> _scanWebDavRecursive(
    MusicSource source,
    String path,
    List<MusicEntity> songs,
    Map<String, String>? headers,
    Set<String> visited,
    Map<String, MusicEntity> existingById,
  ) async {
    // Prevent infinite loops and re-scanning
    if (_cancelScanSignal) return;
    if (visited.contains(path)) return;
    visited.add(path);

    // Rate limiting: delay 100ms between folder requests to prevent being banned
    await Future.delayed(const Duration(milliseconds: 100));

    final entries = await _listWebDavEntries(source, path: path);
    
    for (final e in entries) {
      if (_cancelScanSignal) break;
      if (e.isCollection) {
        await _scanWebDavRecursive(
          source,
          e.href,
          songs,
          headers,
          visited,
          existingById,
        );
      } else {
        final href = _normalizeWebDavHref(e.href, source);
        if (!_isAudioFile(href)) continue;
        final baseSong = MusicEntity(
          id: href,
          title: _webDavNameFromHref(href),
          artist: source.name,
          uri: href,
          isLocal: false,
          headers: headers,
          sourceId: source.id,
        );
        final existing = existingById[href];
        songs.add(_mergeWebDavSong(existing, baseSong, source));
        _bumpScanProgress(processedDelta: 1, addedDelta: 1);
      }
    }
  }

  Future<List<MusicEntity>> _scanWebDavMetadata(
    List<MusicEntity> songs,
    MusicSource source,
  ) async {
    final toScan = songs.where((s) => s.fileSize == null).toList();
    if (toScan.isEmpty) return songs;

    // Notify scanning metadata
    // We can't easily change _scanProcessed/Added count here without messing up total?
    // But we can just run it.

    final queue = Queue<MusicEntity>.from(toScan);
    final results = <MusicEntity>[];
    final workers = <Future<void>>[];
    final concurrency = 3; 

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (_cancelScanSignal) break;
        final song = queue.removeFirst();
        try {
          final remoteMeta = await RemoteMetadataHelper.fetch(song);
          final updated = song.copyWith(
            fileSize: remoteMeta.fileSize ?? song.fileSize,
            bitrate: remoteMeta.bitrate ?? song.bitrate,
            sampleRate: remoteMeta.sampleRate ?? song.sampleRate,
            format: remoteMeta.format ?? song.format,
            durationMs: remoteMeta.duration?.inMilliseconds ?? song.durationMs,
          );
          results.add(updated);
        } catch (e) {
          results.add(song);
        }
        // _bumpScanProgress(processedDelta: 1, addedDelta: 0);
      }
    }

    for (var i = 0; i < concurrency; i++) {
      workers.add(worker());
    }

    await Future.wait(workers);

    final resultMap = {for (var s in results) s.id: s};
    return songs.map((s) => resultMap[s.id] ?? s).toList();
  }

  void _resetScanProgress() {
    _scanProcessed = 0;
    _scanAdded = 0;
    _lastScanNotify = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _bumpScanProgress({required int processedDelta, required int addedDelta}) {
    _scanProcessed += processedDelta;
    _scanAdded += addedDelta;
    final now = DateTime.now();
    if (now.difference(_lastScanNotify).inMilliseconds > 200) {
      _lastScanNotify = now;
      _bump(scanTick);
    }
  }

  bool _hasMeaningfulTitle(MusicEntity song, MusicEntity baseSong) {
    final t = song.title.trim();
    if (t.isEmpty) return false;
    if (t == baseSong.title) return false;
    if (t == '未知标题') return false;
    return true;
  }

  bool _hasMeaningfulArtist(MusicEntity song, MusicEntity baseSong, MusicSource source) {
    final a = song.artist.trim();
    if (a.isEmpty) return false;
    if (a == baseSong.artist) return false;
    if (a == source.name) return false;
    if (a == '未知艺术家') return false;
    return true;
  }

  bool _isWebDavMetadataComplete(
    MusicEntity song,
    MusicEntity baseSong,
    MusicSource source,
  ) {
    final hasTitle = _hasMeaningfulTitle(song, baseSong);
    final hasArtist = _hasMeaningfulArtist(song, baseSong, source);
    final hasAlbum = (song.album ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasLyrics = (song.lyrics ?? '').trim().isNotEmpty;
    return hasTitle || hasArtist || hasAlbum || hasDuration || hasCover || hasLyrics;
  }

  MusicEntity _mergeWebDavSong(
    MusicEntity? existing,
    MusicEntity baseSong,
    MusicSource source,
  ) {
    if (existing == null) return baseSong;
    if (_isWebDavMetadataComplete(existing, baseSong, source)) {
      final safeTitle = existing.title.trim().isNotEmpty ? existing.title : baseSong.title;
      final safeArtist = existing.artist.trim().isNotEmpty ? existing.artist : baseSong.artist;
      return existing.copyWith(
        id: baseSong.id,
        uri: baseSong.uri,
        isLocal: false,
        sourceId: baseSong.sourceId,
        headers: baseSong.headers,
        title: safeTitle,
        artist: safeArtist,
      );
    }
    final title = _hasMeaningfulTitle(existing, baseSong) ? existing.title : baseSong.title;
    final artist = _hasMeaningfulArtist(existing, baseSong, source) ? existing.artist : baseSong.artist;
    final album = (existing.album ?? '').trim().isNotEmpty ? existing.album : baseSong.album;
    final duration = (existing.durationMs ?? 0) > 0
        ? existing.durationMs
        : baseSong.durationMs;
    final lyrics = (existing.lyrics ?? '').trim().isNotEmpty ? existing.lyrics : baseSong.lyrics;
    return baseSong.copyWith(
      title: title,
      artist: artist,
      album: album,
      durationMs: duration,
      localCoverPath: existing.localCoverPath ?? baseSong.localCoverPath,
      localLyricPath: existing.localLyricPath ?? baseSong.localLyricPath,
      lyrics: lyrics,
      fileSize: existing.fileSize ?? baseSong.fileSize,
      bitrate: existing.bitrate ?? baseSong.bitrate,
      sampleRate: existing.sampleRate ?? baseSong.sampleRate,
      format: existing.format ?? baseSong.format,
    );
  }

  Future<void> _replaceSongsForSource(String sourceId, List<MusicEntity> newSongs) async {
    final dbHelper = DatabaseHelper();
    await dbHelper.clearSongsBySource(sourceId);
    await dbHelper.insertSongs(newSongs);
    await _loadCachedSongs();
  }

  Map<String, String>? getHeadersForSource(String sourceId) {
    final source = _findSourceById(sourceId);
    if (source != null) {
      return _buildAuthHeaders(source);
    }
    return null;
  }

  Map<String, String>? _buildAuthHeaders(MusicSource source) {
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    };
    final username = source.username?.trim() ?? '';
    final password = source.password ?? '';
    if (username.isNotEmpty || password.isNotEmpty) {
      final auth = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $auth';
    }
    return headers;
  }

  Future<List<WebDavEntry>> _listWebDavEntries(
    MusicSource source, {
    String? path,
  }) async {
    final endpoint = source.endpoint?.trim() ?? '';
    if (endpoint.isEmpty) return [];

    // We pass empty credentials to newClient to prevent it from handling auth internally.
    // Instead, we manually inject the Authorization header to force Preemptive Authentication.
    // This solves 401 issues with strict servers (e.g. OpenResty) that reject the initial unauthenticated request.
    final client = webdav.newClient(
      endpoint,
      user: '',
      password: '',
      debug: kDebugMode,
    );

    final username = source.username?.trim() ?? '';
    final password = source.password ?? '';
    
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };

    if (username.isNotEmpty || password.isNotEmpty) {
      final auth = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $auth';
    }
    
    // Attempt to force text/xml, though Dio/webdav_client might override it
    headers['Content-Type'] = 'text/xml';
    
    client.setHeaders(headers);

    try {
      // webdav_client requires the path to be checked/listed.
      // If path is empty, it usually defaults to root, but let's be safe.
      var searchPath = path ?? '/';
      if (!searchPath.startsWith('/')) {
        searchPath = '/$searchPath';
      }

      // Ensure trailing slash for directory listing if needed by the client,
      // though webdav_client usually handles it.
      // readDir returns a list of FileInfo
      final files = await client.readDir(searchPath);

      return files.map((f) {
        // FileInfo has name, path, isDirectory, etc.
        // We map it to our WebDavEntry
        return WebDavEntry(
          name: f.name ?? '',
          href: f.path ?? '',
          isCollection: f.isDir ?? false,
        );
      }).toList();
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('WebDAV list error: $e');
        debugPrint('Stack trace: $stack');
      }
      return [];
    }
  }

  String _normalizeWebDavHref(String href, MusicSource source) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    final endpoint = source.endpoint;
    if (endpoint == null || endpoint.isEmpty) return href;
    
    try {
      final baseUri = Uri.parse(endpoint);
      var path = href;
      if (!path.startsWith('/')) {
        path = '/$path';
      }
      final basePath = baseUri.path;
      if (basePath.isNotEmpty && basePath != '/') {
        final normalizedBase = basePath.endsWith('/')
            ? basePath.substring(0, basePath.length - 1)
            : basePath;
        if (!path.startsWith(normalizedBase)) {
          path = '$normalizedBase$path';
        }
      }
      final full = '${baseUri.scheme}://${baseUri.authority}$path';
      return Uri.parse(full).toString();
    } catch (_) {
      return href;
    }
  }

  String _webDavNameFromHref(String href) {
    try {
      final uri = Uri.parse(href);
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.lastWhere((e) => e.isNotEmpty, orElse: () => '');
      }
    } catch (_) {}
    final parts = href.split('/');
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return href;
  }

  bool _isAudioFile(String href) {
    final lower = href.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.opus');
  }

  Future<void> _loadSources() async {
    final raw = StorageUtil.getString(StorageKeys.musicSources);
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw);
      if (list is List) {
        _sources =
            list.map((e) => MusicSource.fromJson(e as Map<String, dynamic>)).toList();
      }
    }

    if (_sources.isEmpty) {
      _sources = [
        const MusicSource(
          id: _localSourceId,
          type: MusicSourceType.local,
          name: '本地音乐',
        ),
      ];
    }

    final endpoint = StorageUtil.getString('webdav_endpoint') ?? '';
    final username = StorageUtil.getString('webdav_username') ?? '';
    final password = StorageUtil.getString('webdav_password') ?? '';
    final path = StorageUtil.getString('webdav_test_path') ?? '';
    if (endpoint.isNotEmpty && _findSourceById(_webDavSourceId) == null) {
      _sources = [
        ..._sources,
        MusicSource(
          id: _webDavSourceId,
          type: MusicSourceType.webdav,
          name: 'WebDAV',
          endpoint: endpoint,
          username: username,
          password: password,
          path: path,
        ),
      ];
      await _saveSources();
    }
    _isSourcesLoaded = true;
    _bump(libraryTick);
  }

  Future<void> _saveSources() async {
    final data = jsonEncode(_sources.map((e) => e.toJson()).toList());
    await StorageUtil.setString(StorageKeys.musicSources, data);
  }

  Future<void> _loadCachedSongs() async {
    _sortKey = StorageUtil.getStringOrDefault(StorageKeys.songsSortKey, defaultValue: 'title');
    _ascending = StorageUtil.getBoolOrDefault(StorageKeys.songsSortAscending, defaultValue: true);

    final dbHelper = DatabaseHelper();
    final all = await dbHelper.getSongs();
    
    final idsToDelete = <String>[];
    final normalized = <MusicEntity>[];
    final toUpdate = <MusicEntity>[];

    for (final song in all) {
      if (song.isLocal && song.uri != null && song.uri!.isNotEmpty && song.id != song.uri) {
        final updated = song.copyWith(id: song.uri);
        normalized.add(updated);
        idsToDelete.add(song.id);
        toUpdate.add(updated);
      } else {
        normalized.add(song);
      }
    }
    
    // Batch update to avoid sequential await loop
    if (toUpdate.isNotEmpty) {
      await dbHelper.insertSongs(toUpdate);
    }

    if (idsToDelete.isNotEmpty) {
      await dbHelper.deleteSongsByIds(idsToDelete);
    }
    
    // Re-attach headers for WebDAV songs since DB doesn't store them
    final fixedSongs = normalized.map((song) {
      if (!song.isLocal && song.sourceId != null) {
        final source = _findSourceById(song.sourceId!);
        if (source != null && source.type == MusicSourceType.webdav) {
          return song.copyWith(headers: _buildAuthHeaders(source));
        }
      }
      return song;
    }).toList();

    _allSongs = _sortSongs(fixedSongs);
    _bump(libraryTick);
  }

  void setSort({String? key, bool? ascending}) {
    if (key != null) {
      _sortKey = key;
      StorageUtil.setString(StorageKeys.songsSortKey, key);
    }
    if (ascending != null) {
      _ascending = ascending;
      StorageUtil.setBool(StorageKeys.songsSortAscending, ascending);
    }
    _allSongs = _sortSongs(_allSongs);
    _bump(libraryTick);
  }

  List<MusicEntity> _sortSongs(List<MusicEntity> list) {
    final sorted = List<MusicEntity>.from(list);
    int m(int a, int b) => _ascending ? a.compareTo(b) : b.compareTo(a);
    final sizeCache = <String, int>{};
    int fileSizeOf(MusicEntity song) {
      if (!song.isLocal) return 0;
      return sizeCache.putIfAbsent(song.id, () {
        final path = song.uri;
        if (path == null || path.isEmpty) return 0;
        try {
          return File(path).lengthSync();
        } catch (_) {
          return 0;
        }
      });
    }
    int modifiedOf(MusicEntity song) => song.fileModifiedMs ?? 0;
    sorted.sort((x, y) {
      int cmp(String a, String b) {
        final pa = PinyinHelper.getPinyin(
          a,
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase();
        final pb = PinyinHelper.getPinyin(
          b,
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase();
        return pa.compareTo(pb);
      }

      switch (_sortKey) {
        case 'artist':
          return m(cmp(x.artist, y.artist), cmp(y.artist, x.artist));
        case 'album':
          return m(cmp(x.album ?? '', y.album ?? ''), cmp(y.album ?? '', x.album ?? ''));
        case 'duration':
          return m((x.durationMs ?? 0).compareTo(y.durationMs ?? 0), (y.durationMs ?? 0).compareTo(x.durationMs ?? 0));
        case 'fileSize':
          return m(fileSizeOf(x).compareTo(fileSizeOf(y)), fileSizeOf(y).compareTo(fileSizeOf(x)));
        case 'recentAdded':
          return m(modifiedOf(x).compareTo(modifiedOf(y)), modifiedOf(y).compareTo(modifiedOf(x)));
        case 'recentModified':
          return m(modifiedOf(x).compareTo(modifiedOf(y)), modifiedOf(y).compareTo(modifiedOf(x)));
        default:
          return m(cmp(x.title, y.title), cmp(y.title, x.title));
      }
    });
    return sorted;
  }

  void clearSongs() {
    _allSongs = [];
    _bump(libraryTick);
  }

  Future<void> removeSongsByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final dbHelper = DatabaseHelper();
    await dbHelper.deleteSongsByIds(ids);
    _allSongs.removeWhere((s) => ids.contains(s.id));
    _bump(libraryTick);
  }

  Future<void> clearLyricsCache() async {
    final dbHelper = DatabaseHelper();
    await dbHelper.clearLyricsCache();
    final next = _allSongs
        .map((s) => s.copyWith(lyrics: null, localLyricPath: null))
        .toList();
    _allSongs = _sortSongs(next);
    _bump(libraryTick);
  }

  void updateSongInLibrary(MusicEntity updated) {
    final index = _allSongs.indexWhere((s) => s.id == updated.id);
    if (index >= 0) {
      final next = List<MusicEntity>.from(_allSongs);
      next[index] = updated;
      _allSongs = _sortSongs(next);
      _bump(libraryTick);
    }
  }
}

class FolderInfo {
  final String id;
  final String name;
  final int count;
  final bool isSystem;
  final AssetPathEntity? entity;

  const FolderInfo({
    required this.id,
    required this.name,
    required this.count,
    this.isSystem = false,
    this.entity,
  });
}

class WebDavEntry {
  final String name;
  final String href;
  final bool isCollection;

  const WebDavEntry({
    required this.name,
    required this.href,
    required this.isCollection,
  });
}
