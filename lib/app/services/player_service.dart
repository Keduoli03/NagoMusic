import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

import 'db/dao/song_dao.dart';
import 'lyrics/lyrics_repository.dart';
import 'artwork_cache_helper.dart';
import 'audio_proxy_server.dart';
import 'cache/audio_cache_service.dart';
import 'metadata/tag_probe_service.dart';
import 'media_notification_service.dart';
import 'stats_service.dart';
import '../state/settings_state.dart';
import '../state/song_state.dart';
export '../state/player_state.dart';
import '../state/player_state.dart';

class PlayerService with WidgetsBindingObserver {
  static final PlayerService instance = PlayerService._internal();
  static const Duration _resolvedSourceTtl = Duration(minutes: 10);
  static const Duration _playingPersistInterval = Duration(seconds: 1);
  static const Duration _idlePersistDelay = Duration(milliseconds: 200);

  final _state = AppPlayerState.instance;

  final AudioPlayer _player = AudioPlayer();
  final AudioCacheService _audioCache = AudioCacheService.instance;
  final AudioProxyServer _proxy = AudioProxyServer.instance;
  final SongDao _songDao = SongDao();
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final StatsService _statsService = StatsService.instance;
  AudioSession? _audioSession;

  ValueNotifier<Duration> get position => _state.position;
  ValueNotifier<Duration?> get duration => _state.duration;
  ValueNotifier<Duration> get bufferedPosition => _state.bufferedPosition;
  ValueNotifier<bool> get isPlaying => _state.isPlaying;
  ValueNotifier<List<SongEntity>> get queue => _state.queue;
  ValueNotifier<int> get currentIndex => _state.currentIndex;
  ValueNotifier<SongEntity?> get currentSong => _state.currentSong;
  ValueNotifier<PlaybackSnapshot> get snapshot => _state.snapshot;
  ValueNotifier<PlaybackMode> get playbackMode => _state.playbackMode;
  ValueNotifier<String?> get sleepTimerDisplayText =>
      _state.sleepTimerDisplayText;
  ValueNotifier<bool> get sleepUntilSongEnd => _state.sleepUntilSongEnd;

  Signal<Duration> get positionSignal => _state.positionSignal;
  Signal<Duration?> get durationSignal => _state.durationSignal;
  Signal<Duration> get bufferedPositionSignal => _state.bufferedPositionSignal;
  Signal<bool> get isPlayingSignal => _state.isPlayingSignal;
  Signal<List<SongEntity>> get queueSignal => _state.queueSignal;
  Signal<int> get currentIndexSignal => _state.currentIndexSignal;
  Signal<SongEntity?> get currentSongSignal => _state.currentSongSignal;
  Signal<PlaybackSnapshot> get snapshotSignal => _state.snapshotSignal;
  Signal<PlaybackMode> get playbackModeSignal => _state.playbackModeSignal;
  Signal<String?> get sleepTimerDisplayTextSignal =>
      _state.sleepTimerDisplayTextSignal;
  Signal<bool> get sleepUntilSongEndSignal => _state.sleepUntilSongEndSignal;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<LoopMode>? _loopModeSub;
  StreamSubscription<bool>? _shuffleSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  Timer? _sleepTimer;
  Timer? _persistTimer;
  Timer? _backgroundAudioKeepAliveTimer;
  _PlaybackRestoreState? _restoreSession;
  Future<void>? _restorePrepareFuture;
  DateTime? _sleepEndAt;
  final Map<String, Future<void>> _probeInflight = {};
  final Map<String, int> _durationPersistedMs = {};
  final Map<String, _ResolvedRemoteSource> _resolvedRemoteSources = {};
  final Map<String, Future<Uri>> _sourceResolveInflight = {};
  bool _restoringState = false;
  bool _isSeeking = false;
  bool _audioInterrupted = false;
  bool _wasPlayingBeforeInterruption = false;
  int _seekSeq = 0;
  DateTime _lastPersistTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSnapshotEmit;
  Timer? _snapshotTimer;
  int _prefetchTriggeredIndex = -1;
  bool _recoveringCurrentSource = false;

  static const String _prefsQueueKey = 'playback_queue_v1';
  static const String _prefsIndexKey = 'playback_index_v1';
  static const String _prefsPositionKey = 'playback_position_v1';
  static const String _prefsModeKey = 'playback_mode_v1';
  static const String _prefsWasPlayingKey = 'playback_was_playing_v1';
  static const String _prefsSongIdKey = 'playback_song_id_v1';

  bool get hasLoadedAudioSource => _player.audioSource != null;

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[PlayerService] $message');
  }

  PlayerService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _stopBackgroundAudioKeepAlive();
      if (isPlaying.value) {
        unawaited(_ensureAudiblePlayback());
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _syncPositionFromPlayer();
      _persistPlaybackStateNow();
      _statsService.flush();
      if (isPlaying.value) {
        _startBackgroundAudioKeepAlive();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _syncPositionFromPlayer();
      _persistPlaybackStateNow();
      _statsService.flush();
    }
  }

  Future<void> _hydrateAndSetCurrentSong(SongEntity song) async {
    if (song.isLocal) return;
    try {
      final cachedList = await _songDao.fetchByIds([song.id]);
      if (cachedList.isNotEmpty) {
        final cached = cachedList.first;
        if (cached.localCoverPath != null &&
            cached.localCoverPath != song.localCoverPath) {
          final updated = song.copyWith(localCoverPath: cached.localCoverPath);
          currentSong.value = updated;
          _warmupPlaybackSources(
            updated,
            nextSong: _nextSongForIndex(queue.value, currentIndex.value),
          );
          _emitSnapshot();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Hydration failed: $e');
    }
  }

  Future<void> _init() async {
    _restoringState = true;
    _persistTimer?.cancel();
    _debugLog('init start');
    await AppPlaybackVolumeSettings.ensureLoaded();
    await WebDavPlaybackSettings.ensureLoaded();
    await AppCacheSettings.ensureLoaded();
    await AppLaunchPlaybackSettings.ensureLoaded();
    final session = await AudioSession.instance;
    _audioSession = session;
    await session.configure(const AudioSessionConfiguration.music());
    _interruptionSub = session.interruptionEventStream.listen(
      _handleAudioInterruption,
    );
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      unawaited(_pausePlayback());
    });
    await _player.setLoopMode(LoopMode.all);
    playbackMode.value = PlaybackMode.loop;
    _positionSub = _player.positionStream.listen((value) {
      if (_isSeeking) return;
      if (_shouldIgnoreZeroPosition(value)) {
        return;
      }
      position.value = value;
      _maybePrefetchByRemaining(value);
      _emitSnapshot();
    });
    _durationSub = _player.durationStream.listen((value) {
      duration.value = value;
      final song = currentSong.value;
      final ms = value?.inMilliseconds ?? 0;
      if (song != null && ms > 0) {
        _maybePersistPlaybackDuration(song, ms);
      }
      _emitSnapshot(force: true);
    });
    _bufferSub = _player.bufferedPositionStream.listen((value) {
      bufferedPosition.value = value;
      _emitSnapshot(force: true);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      final wasPlaying = isPlaying.value;
      isPlaying.value = state.playing;
      _emitSnapshot(force: true);
      if (wasPlaying && !state.playing) {
        _schedulePersistPlaybackState(immediate: true);
      }
    });
    _errorSub = _player.errorStream.listen((error) {
      unawaited(_handlePlayerError(error));
    });
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      currentIndex.value = idx;
      _prefetchTriggeredIndex = -1;
      final list = queue.value;
      if (idx >= 0 && idx < list.length) {
        final song = list[idx];
        final previousSongId = currentSong.value?.id;
        final songChanged = previousSongId != song.id;
        currentSong.value = song;
        if (songChanged) {
          final restoredPosition = _restoreSessionForSong(song)?.position;
          position.value = restoredPosition ?? Duration.zero;
          bufferedPosition.value = Duration.zero;
          duration.value = song.durationMs != null
              ? Duration(milliseconds: song.durationMs!)
              : null;
        }
        _maybeProbeSong(song);
        _scheduleDeferredProbe(song);
        _hydrateAndSetCurrentSong(song);
        _warmupPlaybackSources(song, nextSong: _nextSongForIndex(list, idx));
      } else {
        position.value = Duration.zero;
        bufferedPosition.value = Duration.zero;
        duration.value = null;
      }
      _emitSnapshot(force: true);
    });
    _loopModeSub = _player.loopModeStream.listen((loopMode) {
      if (playbackMode.value == PlaybackMode.shuffle) return;
      playbackMode.value = loopMode == LoopMode.one
          ? PlaybackMode.single
          : PlaybackMode.loop;
      _schedulePersistPlaybackState();
    });
    _shuffleSub = _player.shuffleModeEnabledStream.listen((enabled) {
      if (enabled) {
        playbackMode.value = PlaybackMode.shuffle;
      } else {
        final loopMode = _player.loopMode;
        playbackMode.value = loopMode == LoopMode.one
            ? PlaybackMode.single
            : PlaybackMode.loop;
      }
      _schedulePersistPlaybackState();
    });
    AppPlaybackVolumeSettings.volume.addListener(_handleAppVolumeChanged);
    await _applyAppVolume(AppPlaybackVolumeSettings.volume.value);
    try {
      await _restorePlaybackState();
    } finally {
      _restoringState = false;
    }
    _emitSnapshot(force: true);
    _debugLog('init completed');
  }

  void _handleAppVolumeChanged() {
    unawaited(_applyAppVolume(AppPlaybackVolumeSettings.volume.value));
  }

  Future<void> _applyAppVolume(double value) async {
    try {
      await _player.setVolume(value.clamp(0, 1).toDouble());
    } catch (e) {
      if (kDebugMode) debugPrint('PlayerService set volume failed: $e');
    }
  }

  Future<void> playQueue(List<SongEntity> songs, int startIndex) async {
    _clearRestoreSession();
    final playable = songs
        .where((s) => (s.uri ?? '').trim().isNotEmpty)
        .toList();
    if (playable.isEmpty) return;
    final targetId = startIndex >= 0 && startIndex < songs.length
        ? songs[startIndex].id
        : null;
    var actualIndex = targetId == null
        ? 0
        : playable.indexWhere((s) => s.id == targetId);
    if (actualIndex < 0) actualIndex = 0;
    _debugLog(
      'playQueue size=${playable.length} startIndex=$startIndex actualIndex=$actualIndex song=${playable[actualIndex].title}',
    );
    _applyLogicalQueue(playable, actualIndex);

    Future<bool> setSourcesOnce() async {
      try {
        final sourceQueue = await _buildPlaybackSourceQueue(playable);
        await _loadPlaybackSourceQueue(sourceQueue, initialIndex: actualIndex);
        return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PlayerService.playQueue setAudioSources failed: $e');
        }
        final msg = e.toString();
        final shouldRetry =
            msg.contains('404') ||
            msg.contains('InvalidResponseCodeException') ||
            msg.contains('Source error');
        if (!shouldRetry) return false;

        try {
          await _player.stop();
        } catch (_) {}

        final current = playable[actualIndex];
        final uri = (current.uri ?? '').trim();
        if (!current.isLocal && uri.startsWith('http')) {
          final headers = _headersFromSong(current);
          await _audioCache.removeCachedFiles(uri: uri, headers: headers);
          await TagProbeService.instance.removeRemoteProbeCache(
            uri: uri,
            headers: headers,
          );
        }

        try {
          final sourceQueue = await _buildPlaybackSourceQueue(
            playable,
            forceRefreshSongId: current.id,
          );
          await _loadPlaybackSourceQueue(
            sourceQueue,
            initialIndex: actualIndex,
          );
          return true;
        } catch (e2) {
          if (kDebugMode) {
            debugPrint(
              'PlayerService.playQueue setAudioSources retry failed: $e2',
            );
          }
          return false;
        }
      }
    }

    final ok = await setSourcesOnce();
    if (!ok) {
      try {
        await _player.stop();
      } catch (_) {}
      isPlaying.value = false;
      _emitSnapshot(force: true);
      return;
    }

    if (playbackMode.value == PlaybackMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
      await _player.shuffle();
    }

    try {
      await _player.play();
    } catch (e) {
      try {
        await _player.stop();
      } catch (_) {}
      isPlaying.value = false;
      _emitSnapshot();
      if (kDebugMode) {
        debugPrint('PlayerService.playQueue play failed: $e');
      }
    }
  }

  void _maybePrefetchByRemaining(Duration positionValue) {
    if (!WebDavPlaybackSettings.prefetchEnabled.value) return;
    final total = duration.value;
    if (total == null || total.inMilliseconds <= 0) return;
    final remaining = total - positionValue;
    if (remaining.inSeconds > 30) return;
    final idx = currentIndex.value;
    if (idx < 0 || idx == _prefetchTriggeredIndex) return;
    _prefetchTriggeredIndex = idx;
    _prefetchUpcoming();
  }

  Future<void> _prefetchUpcoming() async {
    if (!WebDavPlaybackSettings.prefetchEnabled.value) return;
    final list = queue.value;
    final startIndex = currentIndex.value;
    if (startIndex < 0 || list.isEmpty) return;
    final nextIndex = startIndex + 1;
    if (nextIndex < 0 || nextIndex >= list.length) return;
    final song = list[nextIndex];
    final raw = (song.uri ?? '').trim();
    if (song.isLocal || !raw.startsWith('http')) return;
    _debugLog('prefetch upcoming index=$nextIndex song=${song.title}');
    final headers = _headersFromSong(song);
    final cached = await _audioCache.getCompleteCachedFile(
      uri: raw,
      headers: headers,
    );
    if (cached != null) return;
    if (WebDavPlaybackSettings.segmentedEnabled.value) {
      _audioCache.startBackgroundDownloadSegmented(
        uri: raw,
        headers: headers,
        maxConcurrentSegments: WebDavPlaybackSettings.segmentConcurrency.value,
      );
    } else {
      _audioCache.startBackgroundDownload(uri: raw, headers: headers);
    }
  }

  Future<void> removeSongsById(
    List<String> ids, {
    bool playNextIfCurrentRemoved = true,
  }) async {
    if (ids.isEmpty) return;
    final toRemove = ids.toSet();

    final current = currentSong.value;
    final oldQueue = queue.value;

    if (current != null && toRemove.contains(current.id)) {
      final remaining = oldQueue
          .where((s) => !toRemove.contains(s.id))
          .toList();
      if (remaining.isEmpty) {
        await stopAndClear();
        return;
      }
      if (!playNextIfCurrentRemoved) {
        await stopAndClear();
        return;
      }
      var nextIndex = currentIndex.value;
      if (nextIndex < 0) nextIndex = 0;
      if (nextIndex >= remaining.length) nextIndex = remaining.length - 1;
      await _reloadQueue(
        remaining,
        nextIndex,
        play: true,
        initialPosition: Duration.zero,
      );
      return;
    }

    if (oldQueue.isEmpty) return;
    final remaining = oldQueue.where((s) => !toRemove.contains(s.id)).toList();
    if (remaining.length == oldQueue.length) return;

    if (current == null) {
      queue.value = remaining;
      currentIndex.value = remaining.isEmpty ? -1 : 0;
      currentSong.value = remaining.isEmpty ? null : remaining.first;
      _emitSnapshot();
      return;
    }

    final nextIndex = remaining.indexWhere((s) => s.id == current.id);
    if (nextIndex < 0) {
      await stopAndClear();
      return;
    }
    final wasPlaying = isPlaying.value;
    final pos = position.value;
    await _reloadQueue(
      remaining,
      nextIndex,
      play: wasPlaying,
      initialPosition: pos,
    );
  }

  Future<void> stopAndClear() async {
    _debugLog('stopAndClear');
    _clearRestoreSession();
    _stopBackgroundAudioKeepAlive();
    try {
      await _player.stop();
    } catch (_) {}
    await _setAudioSessionActive(false);
    isPlaying.value = false;
    position.value = Duration.zero;
    duration.value = null;
    bufferedPosition.value = Duration.zero;
    queue.value = const [];
    currentIndex.value = -1;
    currentSong.value = null;
    _emitSnapshot(force: true);
    await _clearPersistedPlaybackState();
  }

  Future<void> _reloadQueue(
    List<SongEntity> songs,
    int startIndex, {
    required bool play,
    Duration? initialPosition,
  }) async {
    _clearRestoreSession();
    final playable = songs
        .where((s) => (s.uri ?? '').trim().isNotEmpty)
        .toList();
    if (playable.isEmpty) {
      await stopAndClear();
      return;
    }
    var actualIndex = startIndex;
    if (actualIndex < 0) actualIndex = 0;
    if (actualIndex >= playable.length) actualIndex = playable.length - 1;

    _applyLogicalQueue(playable, actualIndex);

    final sourceQueue = await _buildPlaybackSourceQueue(playable);
    try {
      await _loadPlaybackSourceQueue(sourceQueue, initialIndex: actualIndex);
    } catch (e) {
      await stopAndClear();
      if (kDebugMode) {
        debugPrint('PlayerService._reloadQueue setAudioSources failed: $e');
      }
      return;
    }

    final seekPos = initialPosition;
    if (seekPos != null && seekPos > Duration.zero) {
      try {
        await _player.seek(seekPos);
      } catch (_) {}
    }

    if (play) {
      try {
        await _startPlayback();
      } catch (e) {
        await stopAndClear();
        if (kDebugMode) {
          debugPrint('PlayerService._reloadQueue play failed: $e');
        }
      }
    } else {
      try {
        await _pausePlayback();
      } catch (_) {}
    }
  }

  Future<void> _handlePlayerError(PlayerException error) async {
    if (_recoveringCurrentSource) return;
    final failedIndex = error.index;
    final list = queue.value;
    if (failedIndex == null || failedIndex < 0 || failedIndex >= list.length) {
      if (kDebugMode) {
        debugPrint('PlayerService player error without valid index: $error');
      }
      return;
    }

    final failedSong = list[failedIndex];
    final rawUri = (failedSong.uri ?? '').trim();
    if (failedSong.isLocal || !rawUri.startsWith('http')) {
      if (kDebugMode) {
        debugPrint('PlayerService player error on non-remote source: $error');
      }
      return;
    }

    _recoveringCurrentSource = true;
    try {
      final headers = _headersFromSong(failedSong);
      _debugLog(
        'recover current source index=$failedIndex song=${failedSong.title} error=${error.message}',
      );
      await _audioCache.removeCachedFiles(uri: rawUri, headers: headers);
      await TagProbeService.instance.removeRemoteProbeCache(
        uri: rawUri,
        headers: headers,
      );
      _invalidateResolvedSource(failedSong);
      await _resolvePlayableUri(failedSong, forceRefresh: true);

      final wasPlaying = isPlaying.value;
      final seekPos = failedIndex == currentIndex.value
          ? position.value
          : Duration.zero;
      final sourceQueue = await _buildPlaybackSourceQueue(
        list,
        forceRefreshSongId: failedSong.id,
      );
      _applyLogicalQueue(list, failedIndex);
      await _loadPlaybackSourceQueue(sourceQueue, initialIndex: failedIndex);
      if (seekPos > Duration.zero) {
        try {
          await _player.seek(seekPos);
        } catch (_) {}
      }
      if (wasPlaying) {
        await _startPlayback();
      } else {
        await _pausePlayback();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerService current source recovery failed: $e');
      }
    } finally {
      _recoveringCurrentSource = false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _pausePlayback();
    } else {
      await _startPlayback();
    }
  }

  Future<void> play() async {
    await _startPlayback();
  }

  Future<void> pause() async {
    await _pausePlayback();
  }

  Future<void> next() async {
    _clearRestoreSession();
    final wasPlaying = _player.playing;
    await _player.seekToNext();
    if (!wasPlaying) {
      await _startPlayback();
    }
  }

  Future<void> previous() async {
    _clearRestoreSession();
    final wasPlaying = _player.playing;
    await _player.seekToPrevious();
    if (!wasPlaying) {
      await _startPlayback();
    }
  }

  Future<void> seek(Duration position) async {
    _clearRestoreSession();
    _seekSeq++;
    final currentSeq = _seekSeq;
    _isSeeking = true;
    this.position.value = position;
    _emitSnapshot(force: true);
    try {
      await _player.seek(position);
      // Wait a bit for the player to stabilize its position reporting
      if (currentSeq == _seekSeq) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (currentSeq == _seekSeq) {
        _isSeeking = false;
        // Force one last update from the player to ensure sync
        _syncPositionFromPlayer();
        _emitSnapshot(force: true);
        await _persistPlaybackStateNow();
      }
    }
  }

  Future<void> skipToIndex(int index) async {
    _clearRestoreSession();
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> playNext(SongEntity song) async {
    final uri = (song.uri ?? '').trim();
    if (uri.isEmpty) return;

    final oldQueue = queue.value;
    final idx = currentIndex.value;
    final current = currentSong.value;
    if (oldQueue.isEmpty || current == null || idx < 0) {
      await playQueue([song], 0);
      return;
    }

    final insertAt = (idx + 1).clamp(0, oldQueue.length);
    final nextQueue = List<SongEntity>.from(oldQueue);
    nextQueue.insert(insertAt, song);

    final wasPlaying = isPlaying.value;
    final pos = position.value;
    await _reloadQueue(nextQueue, idx, play: wasPlaying, initialPosition: pos);

    if (playbackMode.value == PlaybackMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
    }
  }

  Future<void> insertNext(List<SongEntity> songs) async {
    final toInsert = songs
        .where((s) => (s.uri ?? '').trim().isNotEmpty)
        .toList();
    if (toInsert.isEmpty) return;

    final oldQueue = queue.value;
    final idx = currentIndex.value;
    final current = currentSong.value;
    if (oldQueue.isEmpty || current == null || idx < 0) {
      await playQueue(toInsert, 0);
      return;
    }

    final insertAt = (idx + 1).clamp(0, oldQueue.length);
    final nextQueue = List<SongEntity>.from(oldQueue);
    nextQueue.insertAll(insertAt, toInsert);

    final wasPlaying = isPlaying.value;
    final pos = position.value;
    await _reloadQueue(nextQueue, idx, play: wasPlaying, initialPosition: pos);

    if (playbackMode.value == PlaybackMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
    }
  }

  Future<void> cyclePlaybackMode() async {
    final current = playbackMode.value;
    final next = switch (current) {
      PlaybackMode.shuffle => PlaybackMode.loop,
      PlaybackMode.loop => PlaybackMode.single,
      PlaybackMode.single => PlaybackMode.shuffle,
    };

    playbackMode.value = next;
    if (next == PlaybackMode.shuffle) {
      await _player.setLoopMode(LoopMode.all);
      await _player.setShuffleModeEnabled(true);
      await _player.shuffle();
      _schedulePersistPlaybackState();
      return;
    }
    await _player.setShuffleModeEnabled(false);
    await _player.setLoopMode(
      next == PlaybackMode.single ? LoopMode.one : LoopMode.all,
    );
    _schedulePersistPlaybackState();
  }

  bool get isSleepTimerActive => _sleepTimer != null;

  Duration? get sleepRemaining {
    final end = _sleepEndAt;
    if (end == null) return null;
    return end.difference(DateTime.now());
  }

  void setSleepTimer(Duration duration) {
    _scheduleSleepTimer(duration, untilSongEnd: false);
  }

  void setSleepTimerToSongEnd() {
    final d = duration.value;
    if (d == null || d <= Duration.zero) {
      cancelSleepTimer();
      return;
    }
    final remaining = d - position.value;
    if (remaining <= Duration.zero) {
      cancelSleepTimer();
      _player.pause();
      return;
    }
    _scheduleSleepTimer(remaining, untilSongEnd: true);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndAt = null;
    sleepUntilSongEnd.value = false;
    sleepTimerDisplayText.value = null;
  }

  void _scheduleSleepTimer(Duration duration, {required bool untilSongEnd}) {
    cancelSleepTimer();
    sleepUntilSongEnd.value = untilSongEnd;
    _sleepEndAt = DateTime.now().add(duration);
    _updateSleepTimerText();
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final end = _sleepEndAt;
      if (end == null) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        cancelSleepTimer();
        await _pausePlayback();
        return;
      }
      _updateSleepTimerText();
    });
  }

  void _updateSleepTimerText() {
    final end = _sleepEndAt;
    if (end == null) {
      sleepTimerDisplayText.value = null;
      return;
    }
    final remaining = end.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      sleepTimerDisplayText.value = null;
      return;
    }
    final totalMinutes = remaining.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    sleepTimerDisplayText.value =
        '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  Future<void> clearQueue() async {
    await stopAndClear();
  }

  Future<void> removeFromQueue(int index) async {
    final list = queue.value;
    if (index < 0 || index >= list.length) return;
    await removeSongsById([list[index].id]);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final oldQueue = List<SongEntity>.from(queue.value);
    if (oldQueue.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= oldQueue.length) return;
    if (newIndex < 0 || newIndex > oldQueue.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (targetIndex == oldIndex) return;

    final current = currentSong.value;
    final currentId = current?.id;
    final wasPlaying = isPlaying.value;
    final pos = position.value;

    final item = oldQueue.removeAt(oldIndex);
    oldQueue.insert(targetIndex, item);

    var startIndex = 0;
    if (currentId != null) {
      final idx = oldQueue.indexWhere((s) => s.id == currentId);
      if (idx >= 0) startIndex = idx;
    }

    await _reloadQueue(
      oldQueue,
      startIndex,
      play: wasPlaying,
      initialPosition: pos,
    );

    if (playbackMode.value == PlaybackMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
    }
  }

  void _emitSnapshot({bool force = false}) {
    if (force) {
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      _applySnapshot();
      return;
    }

    final now = DateTime.now();
    final last = _lastSnapshotEmit;

    // If enough time has passed, emit immediately
    if (last == null ||
        now.difference(last) >= const Duration(milliseconds: 250)) {
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      _applySnapshot();
      return;
    }

    // If a timer is already scheduled, do nothing (it will fire at the correct time)
    if (_snapshotTimer != null && _snapshotTimer!.isActive) {
      return;
    }

    final delay = const Duration(milliseconds: 250) - now.difference(last);
    _snapshotTimer = Timer(delay, _applySnapshot);
  }

  void _applySnapshot() {
    _lastSnapshotEmit = DateTime.now();
    final nextSnapshot = PlaybackSnapshot(
      song: currentSong.value,
      queue: queue.value,
      index: currentIndex.value,
      isPlaying: isPlaying.value,
      position: position.value,
      duration: duration.value,
      bufferedPosition: bufferedPosition.value,
    );
    snapshot.value = nextSnapshot;
    _statsService.onSnapshot(nextSnapshot);
    _schedulePersistPlaybackState();
  }

  Future<void> _restorePlaybackState() async {
    final session = await _readPersistedPlaybackState();
    if (session == null) return;
    _debugLog('restorePlaybackState queue=${session.queue.length}');

    final shouldAutoPlayOnLaunch =
        AppLaunchPlaybackSettings.autoPlayOnAppLaunch.value;
    _restorePlaybackUiState(session);
    _restorePrepareFuture = _prepareRestoredAudioSource(session);
    await _restorePrepareFuture;

    if (shouldAutoPlayOnLaunch) {
      try {
        _debugLog('restorePlaybackState autoPlay');
        await _startPlayback();
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Auto play on app launch failed: $e');
        }
      }
    }

    try {
      await _setAudioSessionActive(false);
    } catch (_) {}
  }

  Future<_PlaybackRestoreState?> _readPersistedPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsQueueKey);
    if (raw == null || raw.trim().isEmpty) return null;

    List<SongEntity> restoredQueue = [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        restoredQueue = decoded
            .whereType<Map>()
            .map((e) => SongEntity.fromMap(e.cast<String, dynamic>()))
            .where((s) => (s.uri ?? '').trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      return null;
    }
    if (restoredQueue.isEmpty) return null;

    final savedIndex = prefs.getInt(_prefsIndexKey) ?? 0;
    final savedPositionMs = prefs.getInt(_prefsPositionKey) ?? 0;
    final savedMode = prefs.getString(_prefsModeKey);
    final savedSongId = prefs.getString(_prefsSongIdKey);
    final mode = _playbackModeFromString(savedMode) ?? PlaybackMode.loop;
    var actualIndex = savedIndex;
    if (savedSongId != null && savedSongId.isNotEmpty) {
      final idx = restoredQueue.indexWhere((s) => s.id == savedSongId);
      if (idx >= 0) actualIndex = idx;
    }
    if (actualIndex < 0) actualIndex = 0;
    if (actualIndex >= restoredQueue.length) {
      actualIndex = restoredQueue.length - 1;
    }
    final songId = restoredQueue[actualIndex].id;
    return _PlaybackRestoreState(
      queue: restoredQueue,
      index: actualIndex,
      songId: songId,
      position: Duration(
        milliseconds: savedPositionMs < 0 ? 0 : savedPositionMs,
      ),
      mode: mode,
      wasPlaying: prefs.getBool(_prefsWasPlayingKey) ?? false,
    );
  }

  void _restorePlaybackUiState(_PlaybackRestoreState session) {
    _restoreSession = session;
    _applyLogicalQueue(session.queue, session.index);
    playbackMode.value = session.mode;
    position.value = session.position;
    bufferedPosition.value = Duration.zero;
    final song = session.currentSong;
    duration.value = song.durationMs != null
        ? Duration(milliseconds: song.durationMs!)
        : null;
    isPlaying.value = false;
    _emitSnapshot(force: true);
  }

  Future<void> _prepareRestoredAudioSource(
    _PlaybackRestoreState session,
  ) async {
    try {
      final sourceQueue = await _buildPlaybackSourceQueue(session.queue);
      await _loadPlaybackSourceQueue(
        sourceQueue,
        initialIndex: session.index,
        initialPosition: session.position,
        preload: true,
      );
      if (session.position > Duration.zero) {
        await _seekRestoredPosition(session.position);
      }
      await _applyPlaybackMode(session.mode);
      session
        ..sourcePrepared = true
        ..seekApplied = true;
      position.value = session.position;
      _emitSnapshot(force: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Error restoring playback state: $e');
      session.prepareFailed = true;
    }
  }

  Future<void> _startPlayback() async {
    _debugLog('startPlayback song=${currentSong.value?.title ?? 'none'}');
    await MediaNotificationService.init(force: true);
    final active = await _setAudioSessionActive(true);
    if (!active) {
      throw Exception('Failed to activate audio session');
    }
    await _ensureRestoredPlaybackReady();
    await _player.play();
    _completeRestoreSessionIfReady();
    _startBackgroundAudioKeepAliveIfNeeded();
  }

  Future<void> _pausePlayback() async {
    _debugLog('pausePlayback song=${currentSong.value?.title ?? 'none'}');
    _stopBackgroundAudioKeepAlive();
    await _player.pause();
    _syncPositionFromPlayer(
      allowZeroOverride: !(_restoreSession?.protectPosition ?? false),
    );
    await _persistPlaybackStateNow();
    await _setAudioSessionActive(false);
  }

  void _handleAudioInterruption(AudioInterruptionEvent event) {
    _debugLog(
      'audio interruption begin=${event.begin} type=${event.type.name}',
    );
    if (event.begin) {
      _audioInterrupted = true;
      _wasPlayingBeforeInterruption = isPlaying.value;
      return;
    }
    final shouldResume = _audioInterrupted && _wasPlayingBeforeInterruption;
    _audioInterrupted = false;
    _wasPlayingBeforeInterruption = false;
    if (shouldResume) {
      unawaited(_resumeAfterAudioInterruption());
    }
  }

  Future<void> _resumeAfterAudioInterruption() async {
    try {
      final active = await _setAudioSessionActive(true);
      if (!active) return;
      if (!_player.playing && currentSong.value != null) {
        await _player.play();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerService interruption resume failed: $e');
      }
    }
  }

  void _startBackgroundAudioKeepAliveIfNeeded() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden) {
      _startBackgroundAudioKeepAlive();
    }
  }

  void _startBackgroundAudioKeepAlive() {
    if (_backgroundAudioKeepAliveTimer?.isActive ?? false) return;
    _backgroundAudioKeepAliveTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) {
        if (!isPlaying.value) {
          _stopBackgroundAudioKeepAlive();
          return;
        }
        unawaited(_setAudioSessionActive(true));
      },
    );
  }

  void _stopBackgroundAudioKeepAlive() {
    _backgroundAudioKeepAliveTimer?.cancel();
    _backgroundAudioKeepAliveTimer = null;
  }

  Future<void> _ensureAudiblePlayback() async {
    if (!isPlaying.value || currentSong.value == null) return;
    try {
      await _setAudioSessionActive(true);
      final processing = _player.processingState;
      if (processing == ProcessingState.idle) {
        final list = queue.value;
        final idx = currentIndex.value;
        if (list.isNotEmpty && idx >= 0 && idx < list.length) {
          final pos = position.value;
          final sourceQueue = await _buildPlaybackSourceQueue(list);
          await _loadPlaybackSourceQueue(
            sourceQueue,
            initialIndex: idx,
            initialPosition: pos,
            preload: true,
          );
        }
      }
      if (!_player.playing) {
        await _player.play();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerService ensure audible playback failed: $e');
      }
    }
  }

  Future<void> _ensureRestoredPlaybackReady() async {
    final session = _restoreSession;
    if (session == null || session.prepareFailed) return;
    final preparing = _restorePrepareFuture;
    if (preparing != null) {
      await preparing;
    }
    if (session.seekApplied) return;
    await _seekRestoredPosition(session.position);
    session.seekApplied = true;
  }

  Future<void> _seekRestoredPosition(Duration restored) async {
    _isSeeking = true;
    position.value = restored;
    _emitSnapshot(force: true);
    try {
      await _player.seek(restored);
    } finally {
      _isSeeking = false;
      if (_player.position > Duration.zero) {
        position.value = _player.position;
      } else {
        position.value = restored;
      }
      _emitSnapshot(force: true);
    }
  }

  void _completeRestoreSessionIfReady() {
    final session = _restoreSession;
    if (session == null) return;
    if (!session.seekApplied) return;
    _restoreSession = null;
    _restorePrepareFuture = null;
  }

  void _clearRestoreSession() {
    _restoreSession = null;
    _restorePrepareFuture = null;
  }

  Future<bool> _setAudioSessionActive(bool active) async {
    final session = _audioSession ?? await AudioSession.instance;
    _audioSession = session;
    try {
      _debugLog('audioSession setActive($active)');
      return await session.setActive(active);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerService audio session setActive($active) failed: $e');
      }
      return !active;
    }
  }

  PlaybackMode? _playbackModeFromString(String? value) {
    switch (value) {
      case 'shuffle':
        return PlaybackMode.shuffle;
      case 'loop':
        return PlaybackMode.loop;
      case 'single':
        return PlaybackMode.single;
      default:
        return null;
    }
  }

  Future<void> _applyPlaybackMode(PlaybackMode mode) async {
    if (mode == PlaybackMode.shuffle) {
      await _player.setLoopMode(LoopMode.all);
      await _player.setShuffleModeEnabled(true);
      await _player.shuffle();
      return;
    }
    await _player.setShuffleModeEnabled(false);
    await _player.setLoopMode(
      mode == PlaybackMode.single ? LoopMode.one : LoopMode.all,
    );
  }

  void _schedulePersistPlaybackState({bool immediate = false}) {
    if (_restoringState) return;

    if (immediate) {
      _persistTimer?.cancel();
      _persistTimer = null;
      unawaited(_persistPlaybackStateNow());
      return;
    }

    if (isPlaying.value) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastPersistTime);
      if (elapsed >= _playingPersistInterval) {
        _persistTimer?.cancel();
        _persistTimer = null;
        unawaited(_persistPlaybackStateNow());
        return;
      }

      if (_persistTimer != null && _persistTimer!.isActive) return;
      _persistTimer = Timer(_playingPersistInterval - elapsed, () {
        _persistTimer = null;
        unawaited(_persistPlaybackStateNow());
      });
      return;
    }

    _persistTimer?.cancel();
    _persistTimer = Timer(_idlePersistDelay, () {
      _persistTimer = null;
      unawaited(_persistPlaybackStateNow());
    });
  }

  bool _shouldIgnoreZeroPosition(Duration value) {
    final session = _restoreSession;
    return session != null &&
        session.protectPosition &&
        value == Duration.zero &&
        position.value > Duration.zero;
  }

  _PlaybackRestoreState? _restoreSessionForSong(SongEntity song) {
    final session = _restoreSession;
    if (session == null) return null;
    if (session.songId != song.id) return null;
    return session;
  }

  void _syncPositionFromPlayer({bool allowZeroOverride = true}) {
    if (_isSeeking) return;
    final playerPosition = _player.position;
    if (playerPosition < Duration.zero) return;
    if (!allowZeroOverride &&
        playerPosition == Duration.zero &&
        position.value > Duration.zero) {
      return;
    }
    position.value = playerPosition;
  }

  Future<void> _persistPlaybackStateNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistPlaybackState();
  }

  Future<void> _persistPlaybackState() async {
    _lastPersistTime = DateTime.now();
    final list = queue.value;
    if (list.isEmpty || currentIndex.value < 0) {
      await _clearPersistedPlaybackState();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final serialized = jsonEncode(list.map((e) => e.toMap()).toList());
    await prefs.setString(_prefsQueueKey, serialized);
    await prefs.setInt(_prefsIndexKey, currentIndex.value);
    await prefs.setInt(
      _prefsPositionKey,
      _positionForPersistence().inMilliseconds,
    );
    await prefs.setString(_prefsModeKey, playbackMode.value.name);
    await prefs.setBool(_prefsWasPlayingKey, isPlaying.value);
    final songId = currentSong.value?.id;
    if (songId == null || songId.isEmpty) {
      await prefs.remove(_prefsSongIdKey);
    } else {
      await prefs.setString(_prefsSongIdKey, songId);
    }
  }

  Duration _positionForPersistence() {
    final session = _restoreSession;
    if (session != null && session.protectPosition) {
      if (_player.position > Duration.zero) return _player.position;
      return session.position;
    }
    return position.value;
  }

  Future<void> _clearPersistedPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsQueueKey);
    await prefs.remove(_prefsIndexKey);
    await prefs.remove(_prefsPositionKey);
    await prefs.remove(_prefsModeKey);
    await prefs.remove(_prefsWasPlayingKey);
    await prefs.remove(_prefsSongIdKey);
  }

  Map<String, String>? _headersFromSong(SongEntity song) {
    final raw = (song.headersJson ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  SongEntity? _nextSongForIndex(List<SongEntity> list, int index) {
    final nextIndex = index + 1;
    if (nextIndex < 0 || nextIndex >= list.length) return null;
    return list[nextIndex];
  }

  void _warmupPlaybackSources(SongEntity current, {SongEntity? nextSong}) {
    unawaited(_warmupSource(current));
    if (nextSong != null) {
      unawaited(_warmupSource(nextSong));
    }
  }

  Future<void> _warmupSource(SongEntity song) async {
    final rawUri = (song.uri ?? '').trim();
    if (song.isLocal || !rawUri.startsWith('http')) return;
    try {
      await _resolvePlayableUri(song);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PlayerService warmup source failed for ${song.title}: $e');
      }
    }
  }

  void _invalidateResolvedSource(SongEntity song) {
    _resolvedRemoteSources.remove(song.id);
    _sourceResolveInflight.remove(song.id);
  }

  void _applyLogicalQueue(List<SongEntity> songs, int currentQueueIndex) {
    queue.value = songs;
    currentIndex.value = currentQueueIndex;
    currentSong.value = songs[currentQueueIndex];
    _maybeProbeSong(songs[currentQueueIndex]);
    _hydrateAndSetCurrentSong(songs[currentQueueIndex]);
    _emitSnapshot(force: true);
  }

  Future<_PlaybackSourceQueue> _buildPlaybackSourceQueue(
    List<SongEntity> songs, {
    String? forceRefreshSongId,
  }) async {
    final sources = <AudioSource>[];
    for (final song in songs) {
      sources.add(
        await _sourceForSong(
          song,
          forceRefresh:
              forceRefreshSongId != null && song.id == forceRefreshSongId,
        ),
      );
    }
    return _PlaybackSourceQueue(
      songs: List<SongEntity>.from(songs),
      sources: sources,
    );
  }

  Future<void> _loadPlaybackSourceQueue(
    _PlaybackSourceQueue sourceQueue, {
    required int initialIndex,
    Duration? initialPosition,
    bool preload = false,
  }) async {
    await _player.setAudioSources(
      sourceQueue.sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  String _headersFingerprint(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final pairs = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return pairs.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<Uri> _resolvePlayableUri(
    SongEntity song, {
    bool forceRefresh = false,
  }) async {
    final rawUri = (song.uri ?? '').trim();
    if (song.isLocal || !rawUri.startsWith('http')) {
      return Uri.file(rawUri);
    }

    final headers = _headersFromSong(song);
    final headersKey = _headersFingerprint(headers);
    if (forceRefresh) {
      _invalidateResolvedSource(song);
    }

    final cached = _resolvedRemoteSources[song.id];
    if (cached != null &&
        cached.rawUri == rawUri &&
        cached.headersFingerprint == headersKey &&
        !cached.isExpired) {
      return cached.proxyUri;
    }

    final inflight = _sourceResolveInflight[song.id];
    if (inflight != null) return inflight;

    final future = () async {
      final remoteUri = _getSafeUri(rawUri);
      final finalRemoteUri = remoteUri ?? Uri.parse(rawUri);
      final uriStr = finalRemoteUri.toString();
      final cacheFile = await _audioCache.getCacheFile(
        uri: uriStr,
        headers: headers,
      );
      final proxyUri = await _proxy.registerSource(
        uri: finalRemoteUri,
        headers: {
          ...?headers,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
        },
        cacheFile: cacheFile,
      );
      _resolvedRemoteSources[song.id] = _ResolvedRemoteSource(
        rawUri: rawUri,
        headersFingerprint: headersKey,
        proxyUri: proxyUri,
        resolvedAt: DateTime.now(),
      );
      return proxyUri;
    }();

    _sourceResolveInflight[song.id] = future;
    future.whenComplete(() => _sourceResolveInflight.remove(song.id));
    return future;
  }

  void _maybeProbeSong(SongEntity song) {
    unawaited(_maybeProbeSongAsync(song));
  }

  Future<void> _maybeProbeSongAsync(SongEntity song) async {
    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasLyrics = await _lyricsRepo.hasCachedLrc(song.id);
    final uri = (song.uri ?? '').trim();
    final shouldProbe =
        !song.tagsParsed || !hasCover || !hasDuration || !hasLyrics;
    if (!shouldProbe) return;

    if (song.isLocal) {
      if (uri.isEmpty) return;
      final key =
          'local:${song.id}:${hasCover ? 1 : 0}:${hasDuration ? 1 : 0}:${song.tagsParsed ? 1 : 0}';
      if (_probeInflight.containsKey(key)) return;
      final future = _probeLocalAndPersist(song, uri: uri);
      _probeInflight[key] = future;
      future.whenComplete(() => _probeInflight.remove(key));
      return;
    }

    if (!uri.startsWith('http')) return;

    final headers = _headersFromSong(song);
    final key =
        '${song.id}:${hasCover ? 1 : 0}:${hasDuration ? 1 : 0}:${song.tagsParsed ? 1 : 0}';
    if (_probeInflight.containsKey(key)) return;

    final future = _probeAndPersist(song, uri: uri, headers: headers);
    _probeInflight[key] = future;
    future.whenComplete(() => _probeInflight.remove(key));
  }

  void _scheduleDeferredProbe(SongEntity song) {
    unawaited(_deferredProbe(song));
  }

  Future<void> _deferredProbe(SongEntity song) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final current = currentSong.value;
    if (current == null || current.id != song.id) return;
    _maybeProbeSong(current);
  }

  void _maybePersistPlaybackDuration(SongEntity song, int durationMs) {
    final existing = song.durationMs ?? 0;
    if (existing > 0) return;
    final prev = _durationPersistedMs[song.id] ?? 0;
    if (prev == durationMs) return;
    _durationPersistedMs[song.id] = durationMs;
    _persistSongUpdate(song, durationMs: durationMs);
  }

  Future<void> _persistSongUpdate(
    SongEntity song, {
    int? durationMs,
    String? localCoverPath,
    String? title,
    String? artist,
    String? album,
    int? bitrate,
    int? sampleRate,
    int? fileSize,
    String? format,
    bool? tagsParsed,
  }) async {
    final next = SongEntity(
      id: song.id,
      title: title ?? song.title,
      artist: artist ?? song.artist,
      album: album ?? song.album,
      uri: song.uri,
      isLocal: song.isLocal,
      headersJson: song.headersJson,
      durationMs: durationMs ?? song.durationMs,
      bitrate: bitrate ?? song.bitrate,
      sampleRate: sampleRate ?? song.sampleRate,
      fileSize: fileSize ?? song.fileSize,
      format: format ?? song.format,
      sourceId: song.sourceId,
      fileModifiedMs: song.fileModifiedMs,
      localCoverPath: localCoverPath ?? song.localCoverPath,
      localAssetId: song.localAssetId,
      tagsParsed: tagsParsed ?? song.tagsParsed,
    );

    await _songDao.upsertSongs([next]);

    final list = queue.value;
    final idx = list.indexWhere((e) => e.id == song.id);
    if (idx >= 0) {
      final updatedQueue = [...list];
      updatedQueue[idx] = next;
      queue.value = updatedQueue;
    }

    final current = currentSong.value;
    if (current != null && current.id == song.id) {
      currentSong.value = next;
      _warmupPlaybackSources(
        next,
        nextSong: _nextSongForIndex(queue.value, currentIndex.value),
      );
      _emitSnapshot(force: true);
    }
  }

  Future<void> _probeAndPersist(
    SongEntity song, {
    required String uri,
    Map<String, String>? headers,
  }) async {
    final result = await TagProbeService.instance.probeSongDedup(
      uri: uri,
      isLocal: false,
      headers: headers,
      includeArtwork: true,
    );
    if (result == null) return;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if ((coverPath ?? '').trim().isEmpty &&
        artwork != null &&
        artwork.isNotEmpty) {
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

    final title = (result.title ?? '').trim().isNotEmpty
        ? result.title!.trim()
        : null;
    final artist = (result.artist ?? '').trim().isNotEmpty
        ? result.artist!.trim()
        : null;
    final album = (result.album ?? '').trim().isNotEmpty
        ? result.album!.trim()
        : null;
    await _persistSongUpdate(
      song,
      title: title,
      artist: artist,
      album: album,
      durationMs: result.durationMs,
      bitrate: result.bitrate,
      sampleRate: result.sampleRate,
      fileSize: result.fileSize,
      format: result.format,
      localCoverPath: coverPath,
      tagsParsed: true,
    );
  }

  Future<void> _probeLocalAndPersist(
    SongEntity song, {
    required String uri,
  }) async {
    final result = await TagProbeService.instance.probeSongDedup(
      uri: uri,
      isLocal: true,
      includeArtwork: true,
    );
    if (result == null) return;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if ((coverPath ?? '').trim().isEmpty &&
        artwork != null &&
        artwork.isNotEmpty) {
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

    final title = (result.title ?? '').trim().isNotEmpty
        ? result.title!.trim()
        : null;
    final artist = (result.artist ?? '').trim().isNotEmpty
        ? result.artist!.trim()
        : null;
    final album = (result.album ?? '').trim().isNotEmpty
        ? result.album!.trim()
        : null;
    await _persistSongUpdate(
      song,
      title: title,
      artist: artist,
      album: album,
      durationMs: result.durationMs,
      bitrate: result.bitrate,
      sampleRate: result.sampleRate,
      fileSize: result.fileSize,
      format: result.format,
      localCoverPath: coverPath,
      tagsParsed: true,
    );
  }

  Uri? _getSafeUri(String uriStr) {
    try {
      final uri = Uri.parse(uriStr);
      // Heuristic: If path contains %25 (encoded %), it might be double encoded (e.g. %2520 instead of %20).
      // We want to decode it so that the resulting Uri uses proper single encoding.
      if (uri.path.contains('%25')) {
        try {
          return Uri.parse(Uri.decodeFull(uriStr));
        } catch (_) {
          return uri;
        }
      }
      return uri;
    } catch (_) {
      try {
        return Uri.parse(Uri.encodeFull(uriStr));
      } catch (_) {
        return null;
      }
    }
  }

  Future<AudioSource> _sourceForSong(
    SongEntity song, {
    bool forceRefresh = false,
  }) async {
    final rawUri = (song.uri ?? '').trim();
    if (song.isLocal || !rawUri.startsWith('http')) {
      return AudioSource.file(rawUri);
    }

    final local = await _resolvePlayableUri(song, forceRefresh: forceRefresh);
    return AudioSource.uri(local);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    AppPlaybackVolumeSettings.volume.removeListener(_handleAppVolumeChanged);
    cancelSleepTimer();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferSub?.cancel();
    await _stateSub?.cancel();
    await _indexSub?.cancel();
    await _errorSub?.cancel();
    await _loopModeSub?.cancel();
    await _shuffleSub?.cancel();
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    _stopBackgroundAudioKeepAlive();
    await _setAudioSessionActive(false);
    await _player.dispose();
  }
}

class _ResolvedRemoteSource {
  final String rawUri;
  final String headersFingerprint;
  final Uri proxyUri;
  final DateTime resolvedAt;

  const _ResolvedRemoteSource({
    required this.rawUri,
    required this.headersFingerprint,
    required this.proxyUri,
    required this.resolvedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(resolvedAt) > PlayerService._resolvedSourceTtl;
}

class _PlaybackRestoreState {
  final List<SongEntity> queue;
  final int index;
  final String songId;
  final Duration position;
  final PlaybackMode mode;
  final bool wasPlaying;
  bool sourcePrepared;
  bool seekApplied;
  bool prepareFailed;

  _PlaybackRestoreState({
    required this.queue,
    required this.index,
    required this.songId,
    required this.position,
    required this.mode,
    required this.wasPlaying,
  }) : sourcePrepared = false,
       seekApplied = false,
       prepareFailed = false;

  SongEntity get currentSong => queue[index];

  bool get protectPosition => !seekApplied && position > Duration.zero;
}

class _PlaybackSourceQueue {
  final List<SongEntity> songs;
  final List<AudioSource> sources;

  const _PlaybackSourceQueue({required this.songs, required this.sources});
}
