import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_cache/media_cache.dart';
import 'package:signals/signals.dart';

import 'bili/bili_music_service.dart';
import 'db/dao/song_dao.dart';
import 'media_notification_service.dart';
import 'player/playback_source_resolver.dart';
import 'player/playback_state_persistence.dart';
import 'player/player_sleep_timer.dart';
import 'player/song_metadata_persister.dart';
import 'log/log.dart';
import 'stats_service.dart';
import '../state/settings_state.dart';
import '../state/song_state.dart';
export '../state/player_state.dart';
import '../state/player_state.dart';

class PlayerService with WidgetsBindingObserver {
  static final PlayerService instance = PlayerService._internal();

  final _state = AppPlayerState.instance;

  final AudioPlayer _player = AudioPlayer();
  final AudioCacheService _audioCache = AudioCacheService.instance;
  final SongDao _songDao = SongDao();
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
  late final PlayerSleepTimer _sleepTimer = PlayerSleepTimer(
    onExpire: _pausePlayback,
    sleepUntilSongEnd: _state.sleepUntilSongEnd,
    sleepTimerDisplayText: _state.sleepTimerDisplayText,
  );
  late final SongMetadataPersister _metadataPersister = SongMetadataPersister(
    resolveRawUri: _sourceResolver.resolveWebdavRawUri,
    headersFor: _sourceResolver.headersFromSong,
    onSongPersisted: _handleSongPersisted,
    isCurrentSong: (id) => currentSong.value?.id == id,
  );
  late final PlaybackSourceResolver _sourceResolver = PlaybackSourceResolver();
  late final PlaybackStatePersistence _playbackPersistence =
      PlaybackStatePersistence(
        isRestoring: () => _restoringState,
        isPlaying: () => isPlaying.value,
        queue: () => queue.value,
        currentIndex: () => currentIndex.value,
        mode: () => playbackMode.value,
        currentSongId: () => currentSong.value?.id,
        positionForPersistence: _positionForPersistence,
      );
  Timer? _backgroundAudioKeepAliveTimer;
  PlaybackRestoreState? _restoreSession;
  Future<void>? _restorePrepareFuture;
  bool _restoringState = false;
  bool _isSeeking = false;
  Duration? _seekTarget;
  bool _audioInterrupted = false;
  bool _wasPlayingBeforeInterruption = false;
  int _seekSeq = 0;
  DateTime? _lastSnapshotEmit;
  Timer? _snapshotTimer;
  int _prefetchTriggeredIndex = -1;
  bool _recoveringCurrentSource = false;

  bool get hasLoadedAudioSource => _player.audioSource != null;

  static const String _logTag = 'PlayerService';

  void _debugLog(String message) => AppLog.instance.d(_logTag, message);

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
      _playbackPersistence.persistNow();
      _statsService.flush();
      if (isPlaying.value) {
        _startBackgroundAudioKeepAlive();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _syncPositionFromPlayer();
      _playbackPersistence.persistNow();
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
          // 队列里的那一项也要换掉，否则它会一直是没有封面的旧实例，
          // 下一次 currentIndexStream 发射时又把 currentSong 打回去。
          final list = queue.value;
          final index = list.indexWhere((item) => item.id == song.id);
          if (index >= 0 &&
              list[index].localCoverPath != updated.localCoverPath) {
            final next = [...list];
            next[index] = updated;
            queue.value = next;
          }
          _sourceResolver.warmupPlaybackSources(
            updated,
            nextSong: _nextSongForIndex(queue.value, currentIndex.value),
          );
          _emitSnapshot();
        }
      }
    } catch (e, s) {
      AppLog.instance.w(_logTag, '恢复播放列表元数据失败', e, s);
    }
  }

  Future<void> _init() async {
    _restoringState = true;
    _playbackPersistence.cancelTimer();
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
      if (_isSeeking) {
        // End the seek freeze early once the player reports a position near the
        // requested target, instead of blanking the progress bar for a fixed
        // delay after every seek.
        final target = _seekTarget;
        if (target != null && (value - target).inMilliseconds.abs() <= 600) {
          _isSeeking = false;
          _seekTarget = null;
        } else {
          return;
        }
      }
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
        _metadataPersister.persistPlaybackDuration(song, ms);
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
        _playbackPersistence.schedule(immediate: true);
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
        if (songChanged) {
          currentSong.value = song;
          final restoredPosition = _restoreSessionForSong(song)?.position;
          position.value = restoredPosition ?? Duration.zero;
          bufferedPosition.value = Duration.zero;
          duration.value = song.durationMs != null
              ? Duration(milliseconds: song.durationMs!)
              : null;
        }
        // 还是同一首歌时**不要**重新赋值 currentSong。
        //
        // just_audio 在播放/暂停切换时也会重新发射 currentIndexStream，而
        // 队列里的那个实例往往比 currentSong 更「旧」—— 封面是播放开始后才异步
        // 下载并回填到 currentSong 的，队列元素没跟着更新。一旦覆盖回去，
        // ArtworkWidget 看到 localCoverPath 变了会清空重载（露出占位块）、
        // LyricsService 判定换歌会清空歌词、播放页背景的取色也会重置成主题色，
        // 紧接着 hydrate 又把它补回来 —— 表现就是暂停时整页闪一下。
        _metadataPersister.maybeProbe(song);
        _metadataPersister.scheduleDeferredProbe(song);
        _hydrateAndSetCurrentSong(song);
        _sourceResolver.warmupPlaybackSources(
          song,
          nextSong: _nextSongForIndex(list, idx),
        );
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
      _playbackPersistence.schedule();
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
      _playbackPersistence.schedule();
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '设置音量失败 value=$value', e, s);
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
        final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
          playable,
        );
        await _loadPlaybackSourceQueue(sourceQueue, initialIndex: actualIndex);
        return true;
      } catch (e, s) {
        AppLog.instance.w(_logTag, 'playQueue 装载音源失败，准备重试', e, s);
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
          final headers = _sourceResolver.headersFromSong(current);
          await _audioCache.removeCachedFiles(uri: uri, headers: headers);
          await TagProbeService.instance.removeRemoteProbeCache(
            uri: uri,
            headers: headers,
          );
        }

        try {
          final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
            playable,
            forceRefreshSongId: current.id,
          );
          await _loadPlaybackSourceQueue(
            sourceQueue,
            initialIndex: actualIndex,
          );
          return true;
        } catch (e2, s2) {
          AppLog.instance.e(_logTag, 'playQueue 装载音源重试仍失败', e2, s2);
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
    } catch (e, s) {
      try {
        await _player.stop();
      } catch (_) {}
      isPlaying.value = false;
      _emitSnapshot();
      AppLog.instance.e(_logTag, 'playQueue 起播失败', e, s);
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
    final headers = _sourceResolver.headersFromSong(song);
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
    await _playbackPersistence.clear();
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

    final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
      playable,
    );
    try {
      await _loadPlaybackSourceQueue(sourceQueue, initialIndex: actualIndex);
    } catch (e, s) {
      await stopAndClear();
      AppLog.instance.e(_logTag, '_reloadQueue 装载音源失败', e, s);
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
      } catch (e, s) {
        await stopAndClear();
        AppLog.instance.e(_logTag, '_reloadQueue 起播失败', e, s);
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
      AppLog.instance.w(_logTag, '播放器报错但没有有效的队列下标: $error');
      return;
    }

    final failedSong = list[failedIndex];
    final storedUri = (failedSong.uri ?? '').trim();
    // B 站曲目存的是 `bili://` 占位地址，真实直链是播放时才解析的（见
    // BiliMusicService.resolveStreamUri）。所以不能拿「uri 不是 http」当成
    // 「这是本地文件」—— 那样每一首 B 站歌都会被挡在恢复逻辑外面，直链一过期
    // 就直接放不出来，连一次重新解析都不会尝试。
    //
    // 恢复逻辑本身是通用的：它会 forceRefresh 重新解析，对 B 站正好就是重新取一次
    // playurl，这恰恰是最该做的事。
    final isBili = BiliMusicService.isBiliSong(failedSong);
    if (!isBili && (failedSong.isLocal || !storedUri.startsWith('http'))) {
      AppLog.instance.w(_logTag, '本地音源播放出错，不做在线重定向恢复: $error');
      return;
    }

    _recoveringCurrentSource = true;
    try {
      // Match whatever host was actually in use (may already have been
      // rewritten to an alternate WebDAV address) so cache cleanup targets
      // the right key.
      final rawUri = await _sourceResolver.resolveWebdavRawUri(
        failedSong,
        storedUri,
      );
      final headers = _sourceResolver.headersFromSong(failedSong);
      _debugLog(
        'recover current source index=$failedIndex song=${failedSong.title} error=${error.message}',
      );
      await _audioCache.removeCachedFiles(uri: rawUri, headers: headers);
      await TagProbeService.instance.removeRemoteProbeCache(
        uri: rawUri,
        headers: headers,
      );
      _sourceResolver.invalidateResolvedSource(failedSong);
      await _sourceResolver.resolvePlayableUri(failedSong, forceRefresh: true);

      final wasPlaying = isPlaying.value;
      final seekPos = failedIndex == currentIndex.value
          ? position.value
          : Duration.zero;
      final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
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
    } catch (e, s) {
      AppLog.instance.e(_logTag, '当前音源恢复失败', e, s);
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
    _seekTarget = position;
    this.position.value = position;
    _emitSnapshot(force: true);
    try {
      await _player.seek(position);
      // Bounded settle: returns as soon as the position listener observes a
      // near-target position (usually well under 100ms), capped at 600ms so a
      // misbehaving backend can't freeze the bar indefinitely.
      final start = DateTime.now();
      while (currentSeq == _seekSeq &&
          _isSeeking &&
          DateTime.now().difference(start).inMilliseconds < 600) {
        await Future.delayed(const Duration(milliseconds: 32));
      }
    } finally {
      if (currentSeq == _seekSeq) {
        _isSeeking = false;
        _seekTarget = null;
        // Force one last update from the player to ensure sync
        _syncPositionFromPlayer();
        _emitSnapshot(force: true);
        await _playbackPersistence.persistNow();
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

    await setPlaybackMode(next);
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    playbackMode.value = mode;
    await _applyPlaybackMode(mode);
    _playbackPersistence.schedule();
  }

  bool get isSleepTimerActive => _sleepTimer.isActive;

  Duration? get sleepRemaining => _sleepTimer.remaining;

  void setSleepTimer(Duration duration) {
    _sleepTimer.start(duration, untilSongEnd: false);
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
    _sleepTimer.start(remaining, untilSongEnd: true);
  }

  void cancelSleepTimer() {
    _sleepTimer.cancel();
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
    _playbackPersistence.schedule();
  }

  Future<void> _restorePlaybackState() async {
    final session = await _playbackPersistence.read();
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
      } catch (e, s) {
        AppLog.instance.e(_logTag, '启动自动续播失败', e, s);
      }
    }

    try {
      await _setAudioSessionActive(false);
    } catch (_) {}
  }

  void _restorePlaybackUiState(PlaybackRestoreState session) {
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

  Future<void> _prepareRestoredAudioSource(PlaybackRestoreState session) async {
    try {
      final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
        session.queue,
      );
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
    } catch (e, s) {
      AppLog.instance.e(_logTag, '恢复播放进度失败', e, s);
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
    await _playbackPersistence.persistNow();
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
          final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
            list,
          );
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

  bool _shouldIgnoreZeroPosition(Duration value) {
    final session = _restoreSession;
    return session != null &&
        session.protectPosition &&
        value == Duration.zero &&
        position.value > Duration.zero;
  }

  PlaybackRestoreState? _restoreSessionForSong(SongEntity song) {
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

  Duration _positionForPersistence() {
    final session = _restoreSession;
    if (session != null && session.protectPosition) {
      if (_player.position > Duration.zero) return _player.position;
      return session.position;
    }
    return position.value;
  }

  SongEntity? _nextSongForIndex(List<SongEntity> list, int index) {
    final nextIndex = index + 1;
    if (nextIndex < 0 || nextIndex >= list.length) return null;
    return list[nextIndex];
  }

  void _applyLogicalQueue(List<SongEntity> songs, int currentQueueIndex) {
    queue.value = songs;
    if (songs.isEmpty) {
      currentIndex.value = -1;
      currentSong.value = null;
      _emitSnapshot(force: true);
      return;
    }
    // Clamp defensively: callers can pass an index derived from a since-changed
    // queue (e.g. error handling after the queue shrank), which would throw.
    final safeIndex = currentQueueIndex.clamp(0, songs.length - 1);
    currentIndex.value = safeIndex;
    currentSong.value = songs[safeIndex];
    _metadataPersister.maybeProbe(songs[safeIndex]);
    _hydrateAndSetCurrentSong(songs[safeIndex]);
    _emitSnapshot(force: true);
  }

  Future<void> _loadPlaybackSourceQueue(
    PlaybackSourceQueue sourceQueue, {
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

  /// 曲目回写（[SongMetadataPersister] 写完 DB 后）的联动：更新内存里的队列和
  /// currentSong、预热下一首、发快照。原本在 `_persistSongUpdate` 里，抽出后
  /// 由持有者这边负责 —— 队列 / currentSong 的归属没变。
  void _handleSongPersisted(SongEntity next) {
    final list = queue.value;
    final idx = list.indexWhere((e) => e.id == next.id);
    if (idx >= 0) {
      final updatedQueue = [...list];
      updatedQueue[idx] = next;
      queue.value = updatedQueue;
    }

    final current = currentSong.value;
    if (current != null && current.id == next.id) {
      currentSong.value = next;
      _sourceResolver.warmupPlaybackSources(
        next,
        nextSong: _nextSongForIndex(queue.value, currentIndex.value),
      );
      _emitSnapshot(force: true);
    }
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
