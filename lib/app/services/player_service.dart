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

  /// 当前已经并入 just_audio 播放列表的逻辑下标区间（闭区间），null 表示
  /// 「这个队列没有走增量加载」——要么还没起播，要么走的是随机播放/远跳这类
  /// 维持整队列一次性装载的老路径。
  ///
  /// 核心不变式：只要某个逻辑下标落在这个区间里，它在 just_audio 播放列表里的
  /// 物理下标就**等于**这个逻辑下标本身——增量加载只往队头/队尾接，不做稀疏乱序
  /// 拼接。`_indexSub`、播放持久化、`_handlePlayerError` 全都直接拿 `queue.value
  /// [idx]`，靠的就是这条假设，所以不能破坏它。
  int? _loadedLo;
  int? _loadedHi;

  void _setLoadedRange(int lo, int hi) {
    _loadedLo = lo;
    _loadedHi = hi;
  }

  void _clearLoadedRange() {
    _loadedLo = null;
    _loadedHi = null;
  }

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
        // 下一首的音频字节从这首一开始播就下载，而不是等到只剩 30 秒才动手
        // （见 _maybePrefetchByRemaining）。原来的窗口在短歌、慢网络、大文件
        // 上根本不够用——后台下载还没写完最终文件，切歌那一刻 proxy 发现文件
        // 不完整，只能重新对源服务器发起一次网络请求，跟完全没预取一样得等。
        // 现在给足整首歌的时长去下，慢网络也大概率能在切歌前下完。
        // startBackgroundDownload 内部按 uri+headers 去重，跟后面 30 秒那次
        // 重复触发不会重复下载。
        _prefetchUpcoming();
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
    _clearLoadedRange();

    Future<bool> setSourcesOnce() async {
      try {
        final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
          playable,
        );
        final generation = await _loadPlaybackSourceQueue(
          sourceQueue,
          initialIndex: actualIndex,
        );
        if (generation == _loadGeneration) {
          _setLoadedRange(0, playable.length - 1);
        }
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
          final generation = await _loadPlaybackSourceQueue(
            sourceQueue,
            initialIndex: actualIndex,
          );
          if (generation == _loadGeneration) {
            _setLoadedRange(0, playable.length - 1);
          }
          return true;
        } catch (e2, s2) {
          AppLog.instance.e(_logTag, 'playQueue 装载音源重试仍失败', e2, s2);
          return false;
        }
      }
    }

    // 随机播放需要对完整播放列表算洗牌顺序，边填充边洗很难保证正确，维持整
    // 队列一次性装载。其余模式走增量：只建当前这首就能起播，其余交给后台。
    var ok = playbackMode.value == PlaybackMode.shuffle
        ? false
        : await _loadIncremental(playable, actualIndex);
    if (!ok) {
      ok = await setSourcesOnce();
    }
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
    _clearLoadedRange();
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
    _clearLoadedRange();

    final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
      playable,
    );
    try {
      final generation = await _loadPlaybackSourceQueue(
        sourceQueue,
        initialIndex: actualIndex,
      );
      if (generation == _loadGeneration) {
        _setLoadedRange(0, playable.length - 1);
      }
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
      final generation = await _loadPlaybackSourceQueue(
        sourceQueue,
        initialIndex: failedIndex,
      );
      if (generation == _loadGeneration) {
        _setLoadedRange(0, list.length - 1);
      }
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
    final targetIndex = currentIndex.value + 1;
    if (targetIndex < queue.value.length) {
      await _ensureLogicalIndexLoaded(targetIndex, forward: true);
    }
    final wasPlaying = _player.playing;
    await _player.seekToNext();
    if (!wasPlaying) {
      await _startPlayback();
    }
  }

  Future<void> previous() async {
    _clearRestoreSession();
    final targetIndex = currentIndex.value - 1;
    if (targetIndex >= 0) {
      await _ensureLogicalIndexLoaded(targetIndex, forward: false);
    }
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
    final lo = _loadedLo;
    final hi = _loadedHi;
    if (lo != null && hi != null && (index < lo || index > hi)) {
      await _reloadForFarJump(index);
      return;
    }
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
      // 随机播放模式维持整队列一次性装载（原因同 playQueue）；其余模式先把
      // 上次播放的这首装上——这正是"恢复卡好几秒"最常撞见的场景：上次退出时
      // 队列可能是整个几千首的 WebDAV 音源。
      final ok = session.mode == PlaybackMode.shuffle
          ? false
          : await _loadIncremental(
              session.queue,
              session.index,
              initialPosition: session.position,
              preload: true,
            );
      if (!ok) {
        final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(
          session.queue,
        );
        final generation = await _loadPlaybackSourceQueue(
          sourceQueue,
          initialIndex: session.index,
          initialPosition: session.position,
          preload: true,
        );
        if (generation == _loadGeneration) {
          _setLoadedRange(0, session.queue.length - 1);
        }
      }
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
          final generation = await _loadPlaybackSourceQueue(
            sourceQueue,
            initialIndex: idx,
            initialPosition: pos,
            preload: true,
          );
          // 整队列重新建源装载完了，不管之前是不是走的增量加载，现在都是
          // 全量状态——不重置的话 _loadedLo/_loadedHi 还留着旧区间，next/
          // previous 的按需补齐会以为有些其实已经装好的下标还没加载。
          if (generation == _loadGeneration) {
            _setLoadedRange(0, list.length - 1);
          }
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

  /// 正在进行的 `setAudioSources`，以及它的代号。
  ///
  /// just_audio 的 `load` 不可重入：上一次还没走完就再调一次，前一次会以
  /// "Loading interrupted" 失败。而失败会走进 [_handlePlayerError]，那里又会再装载
  /// 一次 —— 于是用户连点两首歌就能把自己卡在原地。这里把装载串行化，并且**后来
  /// 的请求赢**：排队期间又来了新的装载，前面那个直接放弃，不去覆盖用户最新的选择。
  int _loadGeneration = 0;
  Future<void>? _pendingLoad;

  Future<int> _loadPlaybackSourceQueue(
    PlaybackSourceQueue sourceQueue, {
    required int initialIndex,
    Duration? initialPosition,
    bool preload = false,
  }) async {
    final generation = ++_loadGeneration;

    final previous = _pendingLoad;
    if (previous != null) {
      // 前一次的成败与本次无关：它自己的调用方会处理，这里只负责等它腾出位置。
      try {
        await previous;
      } catch (_) {}
      // 等待期间又来了更新的装载请求——这次直接放弃，不调 setAudioSources。
      // 返回的代号仍然是"我原本申请到的那个"，调用方（增量加载的后台填充）
      // 靠它发现自己已经过期，不会带着一个作废的代号继续往队列里塞歌。
      if (generation != _loadGeneration) return generation;
    }

    final future = _player.setAudioSources(
      sourceQueue.sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      preload: preload,
    );
    _pendingLoad = future;
    try {
      await future;
    } finally {
      if (identical(_pendingLoad, future)) _pendingLoad = null;
    }
    return generation;
  }

  // ------------------------------------------------------------ 增量加载队列
  //
  // 目标：点一首歌 / 恢复播放的耗时只取决于「这一首歌」能不能建源，跟队列有
  // 多长无关。只用于 playQueue / 恢复播放这两个冷启动路径，且仅在非随机播放
  // 模式下生效——理由见 lib 外的方案文档，这里不重复。
  //
  // 核心不变式：只要某个逻辑下标已经并入 just_audio 播放列表，它在 just_audio
  // 里的物理下标就**等于**这个逻辑下标本身——只会往队头/队尾接，不做稀疏乱序
  // 拼接。`_indexSub`、播放持久化、`_handlePlayerError` 全都直接拿
  // `queue.value[idx]`，靠的就是这条假设。

  /// 只建目标歌的源、立即装载，队列其余部分交给 [_fillQueueInBackground]
  /// 异步补上。失败返回 false，调用方应当回退到整队列建源（唯一能保证「这次
  /// 真的能放」的路径，代价是变慢，但至少正确）。
  Future<bool> _loadIncremental(
    List<SongEntity> playable,
    int actualIndex, {
    Duration? initialPosition,
    bool preload = false,
  }) async {
    final AudioSource source;
    try {
      source = await _sourceResolver.sourceForSong(playable[actualIndex]);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '增量装载建源失败，回退整队列建源', e, s);
      return false;
    }

    final int generation;
    try {
      generation = await _loadPlaybackSourceQueue(
        PlaybackSourceQueue(songs: [playable[actualIndex]], sources: [source]),
        initialIndex: 0,
        initialPosition: initialPosition,
        preload: preload,
      );
    } catch (e, s) {
      AppLog.instance.w(_logTag, '增量装载首曲失败，回退整队列建源', e, s);
      return false;
    }

    // 这次装载在排队等待期间被更新的请求取代了——不算失败（那个更新的请求会
    // 自己把播放器带到正确状态），但没必要再为这份已经过期的队列跑后台填充。
    if (generation == _loadGeneration) {
      _setLoadedRange(actualIndex, actualIndex);
      unawaited(_fillQueueInBackground(playable, actualIndex, generation));
    }
    return true;
  }

  /// 按「先补后面、再补前面」的顺序，把 [playable] 里除 [actualIndex] 之外的
  /// 部分陆续接上 just_audio 播放列表。
  ///
  /// 先补后面是因为「下一首」比「上一首」常用得多，优先让顺着往下播不用等。
  /// 每一步都先并发建源（复用 [PlaybackSourceResolver.buildPlaybackSourceQueue]，
  /// 跟 playQueue 整队列建源用的是同一套并发逻辑），再一次性 `addAudioSources`/
  /// `insertAudioSources` 接上，不是一首首插——那样会让 just_audio 的播放列表
  /// 中途处于「乱序」状态更久，也更容易撞见平台层的重入限制。
  ///
  /// [generation] 是这次装载在 [_loadPlaybackSourceQueue] 里拿到的代号：期间
  /// 只要 [_loadGeneration] 变了（用户切到了别的队列），立刻放弃——不然一个
  /// 几千首的后台填充任务可能在用户已经在听别的歌之后，还在悄悄往一个已经不
  /// 相关的播放列表里塞歌。
  Future<void> _fillQueueInBackground(
    List<SongEntity> playable,
    int actualIndex,
    int generation,
  ) async {
    try {
      if (actualIndex + 1 < playable.length) {
        final suffixQueue = await _sourceResolver.buildPlaybackSourceQueue(
          playable.sublist(actualIndex + 1),
        );
        if (generation != _loadGeneration) return;
        await _player.addAudioSources(suffixQueue.sources);
        if (generation != _loadGeneration) return;
        _loadedHi = playable.length - 1;
      }
      if (actualIndex > 0) {
        final prefixQueue = await _sourceResolver.buildPlaybackSourceQueue(
          playable.sublist(0, actualIndex),
        );
        if (generation != _loadGeneration) return;
        await _player.insertAudioSources(0, prefixQueue.sources);
        if (generation != _loadGeneration) return;
        _loadedLo = 0;
      }
    } catch (e, s) {
      // 后台补全失败不影响正在播的这首——真播到还没补上的那首时，
      // _handlePlayerError 会走它自己的整队列重建兜底。
      AppLog.instance.w(_logTag, '后台补全播放队列失败', e, s);
    }
  }

  /// [next] / [previous] 在目标下标还没并入 just_audio 播放列表时的兜底：只有
  /// 目标正好紧邻已加载区间的边界（`hi+1` 或 `lo-1`）时才处理——单独建这一首
  /// 的源，跟建当前这首一样快。落在区间外（远跳）的情况不在这里处理，调用方
  /// 各自决定怎么退化。
  Future<void> _ensureLogicalIndexLoaded(
    int index, {
    required bool forward,
  }) async {
    final lo = _loadedLo;
    final hi = _loadedHi;
    // null 表示没有走增量加载（随机播放、或远跳之后已经整队列装载完）——
    // 那种情况下队列要么整段都在，要么整段都不在，不需要这层兜底。
    if (lo == null || hi == null) return;
    if (index >= lo && index <= hi) return;

    final list = queue.value;
    if (index < 0 || index >= list.length) return;
    if (forward && index != hi + 1) return;
    if (!forward && index != lo - 1) return;

    final generation = _loadGeneration;
    try {
      final source = await _sourceResolver.sourceForSong(list[index]);
      if (generation != _loadGeneration) return;
      if (forward) {
        await _player.addAudioSources([source]);
        if (generation != _loadGeneration) return;
        _loadedHi = index;
      } else {
        await _player.insertAudioSources(0, [source]);
        if (generation != _loadGeneration) return;
        _loadedLo = index;
      }
    } catch (e, s) {
      AppLog.instance.w(_logTag, '按需补齐下标 $index 失败', e, s);
    }
  }

  /// [skipToIndex] 跳到增量加载区间之外的下标时的兜底：沿用整队列重新建源
  /// 装载，装载完成后整条队列都在 just_audio 里了，回到「全量加载」状态。
  ///
  /// 这类「跳到队列里很远的一首」本次没有做增量化——要正确处理需要支持稀疏
  /// 区间的物理下标换算，复杂度和收益不成比例，见方案文档。
  Future<void> _reloadForFarJump(int index) async {
    final list = queue.value;
    if (index < 0 || index >= list.length) return;
    final wasPlaying = _player.playing;
    try {
      final sourceQueue = await _sourceResolver.buildPlaybackSourceQueue(list);
      final generation = await _loadPlaybackSourceQueue(
        sourceQueue,
        initialIndex: index,
      );
      if (generation == _loadGeneration) {
        _setLoadedRange(0, list.length - 1);
      }
      if (wasPlaying) {
        await _startPlayback();
      }
    } catch (e, s) {
      AppLog.instance.e(_logTag, '跳转到下标 $index 失败', e, s);
    }
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

  /// 外部（在线匹配、标签编辑等不经过 [SongMetadataPersister] 的写路径）改完
  /// 一首歌后，用这个把变化同步进播放器的内存状态。
  ///
  /// 各个列表页的「在线匹配」入口各自维护自己的本地列表，但没有一个会去碰
  /// `currentSong`/`queue`——歌单页、歌曲页、文件夹页各刷各的，唯独播放器这份
  /// 没人管。碰巧改的是正在播的这首时，DB 和封面文件都已经落盘，播放器内存里
  /// 的 [SongEntity] 却还是旧的：迷你播放条、通知栏、状态栏歌词全部读的是这份
  /// 旧实例，退出播放页重进也一样——因为播放页本身也是照着 currentSong 画的。
  ///
  /// 逻辑和 [_handleSongPersisted] 完全一致（同一份队列/currentSong 由持有者
  /// 维护的规则），只是入口从「探测器回调」换成「任意外部调用方」。
  void refreshSongMetadata(SongEntity next) => _handleSongPersisted(next);

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
