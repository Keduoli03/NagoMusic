import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/artwork_service.dart';
import '../../app/services/http_utils.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/state/song_state.dart';

class SongsArtworkCoordinator {
  static const bool _debugArtwork = false;
  static const int _artworkMaxConcurrent = 3;
  static const int _artworkCacheMax = 300;

  static final LinkedHashMap<String, Uint8List> _artworkCache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _artworkLoading =
      <String, Future<Uint8List?>>{};
  static final List<_ArtworkTask> _artworkQueue = <_ArtworkTask>[];
  static int _artworkActive = 0;

  final ArtworkService _artworkService;
  final SongDao _songDao;

  String _lastPrefetchKey = '';
  int _lastPrefetchCount = -1;

  SongsArtworkCoordinator({ArtworkService? artworkService, SongDao? songDao})
    : _artworkService = artworkService ?? ArtworkService.instance,
      _songDao = songDao ?? SongDao();

  void clearSong(String songId, {String? uri}) {
    _artworkCache.remove(songId);
    _artworkLoading.remove(songId);
    _artworkQueue.removeWhere((t) => t.song.id == songId);
    _artworkService.clearByUri(uri);
  }

  Future<Uint8List?> loadArtwork(
    SongEntity song, {
    required bool cacheArtworkEnabled,
    required void Function(SongEntity updatedSong) onSongUpdated,
  }) {
    if (kDebugMode && _debugArtwork) {
      debugPrint(
        '[SongsArtwork] enqueue id=${song.id} asset=${song.localAssetId} cover=${song.localCoverPath} local=${song.isLocal}',
      );
    }
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
    _artworkQueue.add(
      _ArtworkTask(
        song,
        completer,
        cacheArtworkEnabled: cacheArtworkEnabled,
        onSongUpdated: onSongUpdated,
      ),
    );
    _drainArtworkQueue();
    return completer.future.whenComplete(() => _artworkLoading.remove(id));
  }

  void scheduleRangePrefetch(
    int start,
    int end,
    List<SongEntity> songs, {
    required bool enabled,
    required String sourceFilter,
    required String sortKey,
    required bool ascending,
    required bool cacheArtworkEnabled,
    bool prunePendingOutsideRange = false,
    required void Function(SongEntity updatedSong) onSongUpdated,
  }) {
    if (songs.isEmpty || !enabled) return;
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end >= songs.length ? songs.length - 1 : end;
    if (safeEnd < safeStart) return;
    final key = '$sourceFilter|$sortKey|$ascending|$start|$end|${songs.length}';
    if (key == _lastPrefetchKey && songs.length == _lastPrefetchCount) return;
    _lastPrefetchKey = key;
    _lastPrefetchCount = songs.length;
    if (prunePendingOutsideRange) {
      _prunePendingOutsideRange(songs, safeStart, safeEnd);
    }
    Future.microtask(
      () => _prefetchArtworkRange(
        songs,
        safeStart,
        safeEnd,
        cacheArtworkEnabled: cacheArtworkEnabled,
        onSongUpdated: onSongUpdated,
      ),
    );
  }

  void _prefetchArtworkRange(
    List<SongEntity> songs,
    int start,
    int end, {
    required bool cacheArtworkEnabled,
    required void Function(SongEntity updatedSong) onSongUpdated,
  }) {
    if (songs.isEmpty) return;
    final safeStart = start < 0 ? 0 : start;
    final safeEnd = end >= songs.length ? songs.length - 1 : end;
    if (safeEnd < safeStart) return;
    for (var i = safeEnd; i >= safeStart; i--) {
      final song = songs[i];
      final hasLocalCover = (song.localCoverPath ?? '').trim().isNotEmpty;
      // Prefetch both local and remote covers; skip only those already cached.
      if (hasLocalCover) continue;
      unawaited(
        loadArtwork(
          song,
          cacheArtworkEnabled: cacheArtworkEnabled,
          onSongUpdated: onSongUpdated,
        ),
      );
    }
  }

  void _prunePendingOutsideRange(
    List<SongEntity> songs,
    int safeStart,
    int safeEnd,
  ) {
    final retainedIds = <String>{};
    for (var i = safeStart; i <= safeEnd; i++) {
      retainedIds.add(songs[i].id);
    }
    _artworkQueue.removeWhere((task) {
      if (retainedIds.contains(task.song.id)) return false;
      _artworkLoading.remove(task.song.id);
      if (!task.completer.isCompleted) {
        task.completer.complete(null);
      }
      return true;
    });
  }

  void _drainArtworkQueue() {
    while (_artworkActive < _artworkMaxConcurrent && _artworkQueue.isNotEmpty) {
      final task = _artworkQueue.removeLast();
      _artworkActive += 1;
      _loadArtworkInternal(
            task.song,
            cacheArtworkEnabled: task.cacheArtworkEnabled,
            onSongUpdated: task.onSongUpdated,
          )
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

  Future<Uint8List?> _loadArtworkInternal(
    SongEntity song, {
    required bool cacheArtworkEnabled,
    required void Function(SongEntity updatedSong) onSongUpdated,
  }) async {
    final cachedPath = song.localCoverPath;
    if (cachedPath != null && cachedPath.isNotEmpty) {
      final file = File(cachedPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          if (kDebugMode && _debugArtwork) {
            debugPrint(
              '[SongsArtwork] file hit id=${song.id} cover=$cachedPath bytes=${bytes.length}',
            );
          }
          _rememberArtwork(song.id, bytes);
          return bytes;
        }
      }
    }
    // Remote songs also resolve their cover here (e.g. embedded art fetched by
    // ArtworkService), matching the player/mini-player. The result is cached and
    // its path persisted, so it's a one-time fetch per song.
    try {
      final resolvedAssetId = (song.localAssetId ?? '').trim();
      if (kDebugMode && _debugArtwork) {
        debugPrint(
          '[SongsArtwork] resolved id=${song.id} asset=$resolvedAssetId uri=${song.uri}',
        );
      }
      final bytes = await _artworkService.loadArtworkBytes(
        uri: song.uri,
        localCoverPath: song.localCoverPath,
        localAssetId: resolvedAssetId,
        isLocal: song.isLocal,
        preferOriginal: false,
      );
      if (bytes == null || bytes.isEmpty) {
        if (kDebugMode && _debugArtwork) {
          debugPrint(
            '[SongsArtwork] empty bytes id=${song.id} asset=$resolvedAssetId uri=${song.uri}',
          );
        }
        return null;
      }

      String? cachedPath = song.localCoverPath;
      if ((song.localCoverPath ?? '').trim().isEmpty) {
        final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
          bytes: bytes,
          key: '${song.id}_${song.fileModifiedMs ?? 0}',
        );
        if (cached != null && cached.isNotEmpty) {
          cachedPath = cached;
          if (kDebugMode && _debugArtwork) {
            debugPrint(
              '[SongsArtwork] cached id=${song.id} path=$cached bytes=${bytes.length}',
            );
          }
        } else if (kDebugMode && _debugArtwork) {
          debugPrint('[SongsArtwork] cache failed id=${song.id}');
        }
      }
      final shouldUpdateAssetId =
          resolvedAssetId.isNotEmpty &&
          resolvedAssetId != (song.localAssetId ?? '').trim();
      final shouldUpdateCover =
          (cachedPath ?? '').trim().isNotEmpty &&
          (cachedPath ?? '').trim() != (song.localCoverPath ?? '').trim();
      if (shouldUpdateAssetId || shouldUpdateCover) {
        final updated = song.copyWith(
          localAssetId: shouldUpdateAssetId
              ? resolvedAssetId
              : song.localAssetId,
          localCoverPath: shouldUpdateCover ? cachedPath : song.localCoverPath,
        );
        if (kDebugMode && _debugArtwork) {
          debugPrint(
            '[SongsArtwork] persist id=${song.id} asset=${updated.localAssetId} cover=${updated.localCoverPath}',
          );
        }
        unawaited(_songDao.upsertSongs([updated]));
        onSongUpdated(updated);
      }
      _rememberArtwork(song.id, bytes);
      return bytes;
    } catch (_) {
      if (kDebugMode && _debugArtwork) {
        debugPrint(
          '[SongsArtwork] load failed id=${song.id} uri=${HttpUtils.redactUrl(song.uri)}',
        );
      }
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
}

class _ArtworkTask {
  final SongEntity song;
  final Completer<Uint8List?> completer;
  final bool cacheArtworkEnabled;
  final void Function(SongEntity updatedSong) onSongUpdated;

  _ArtworkTask(
    this.song,
    this.completer, {
    required this.cacheArtworkEnabled,
    required this.onSongUpdated,
  });
}
