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
import '../state/settings_state.dart';
import '../state/song_state.dart';
export '../state/player_state.dart';
import '../state/player_state.dart';

class PlayerService with WidgetsBindingObserver {
  static final PlayerService instance = PlayerService._internal();

  final _state = AppPlayerState.instance;

  final AudioPlayer _player = AudioPlayer();
  final AudioCacheService _audioCache = AudioCacheService.instance;
  final AudioProxyServer _proxy = AudioProxyServer.instance;
  final SongDao _songDao = SongDao();
  final LyricsRepository _lyricsRepo = LyricsRepository();

  ValueNotifier<Duration> get position => _state.position;
  ValueNotifier<Duration?> get duration => _state.duration;
  ValueNotifier<Duration> get bufferedPosition => _state.bufferedPosition;
  ValueNotifier<bool> get isPlaying => _state.isPlaying;
  ValueNotifier<List<SongEntity>> get queue => _state.queue;
  ValueNotifier<int> get currentIndex => _state.currentIndex;
  ValueNotifier<SongEntity?> get currentSong => _state.currentSong;
  ValueNotifier<PlaybackSnapshot> get snapshot => _state.snapshot;
  ValueNotifier<PlaybackMode> get playbackMode => _state.playbackMode;
  ValueNotifier<String?> get sleepTimerDisplayText => _state.sleepTimerDisplayText;
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
  Signal<String?> get sleepTimerDisplayTextSignal => _state.sleepTimerDisplayTextSignal;
  Signal<bool> get sleepUntilSongEndSignal => _state.sleepUntilSongEndSignal;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<LoopMode>? _loopModeSub;
  StreamSubscription<bool>? _shuffleSub;
  Timer? _sleepTimer;
  Timer? _persistTimer;
  DateTime? _sleepEndAt;
  final Map<String, Future<void>> _probeInflight = {};
  final Map<String, int> _durationPersistedMs = {};
  bool _restoringState = false;
  bool _isSeeking = false;
  int _seekSeq = 0;
  DateTime _lastPersistTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSnapshotEmit;
  Timer? _snapshotTimer;
  int _prefetchTriggeredIndex = -1;

  static const String _prefsQueueKey = 'playback_queue_v1';
  static const String _prefsIndexKey = 'playback_index_v1';
  static const String _prefsPositionKey = 'playback_position_v1';
  static const String _prefsModeKey = 'playback_mode_v1';
  static const String _prefsWasPlayingKey = 'playback_was_playing_v1';
  static const String _prefsSongIdKey = 'playback_song_id_v1';

  PlayerService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Force save when app goes to background or is killed
      _persistPlaybackState();
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
          final updated = song.copyWith(
            localCoverPath: cached.localCoverPath,
          );
          currentSong.value = updated;
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
    await WebDavPlaybackSettings.ensureLoaded();
    await AppCacheSettings.ensureLoaded();
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _player.setLoopMode(LoopMode.all);
    playbackMode.value = PlaybackMode.loop;
    _positionSub = _player.positionStream.listen((value) {
      if (_isSeeking) return;
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
      isPlaying.value = state.playing;
      _emitSnapshot(force: true);
    });
    _indexSub = _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      currentIndex.value = idx;
      _prefetchTriggeredIndex = -1;
      final list = queue.value;
      if (idx >= 0 && idx < list.length) {
        final song = list[idx];
        currentSong.value = song;
        _maybeProbeSong(song);
        _hydrateAndSetCurrentSong(song);
      }
      _emitSnapshot(force: true);
    });
    _loopModeSub = _player.loopModeStream.listen((loopMode) {
      if (playbackMode.value == PlaybackMode.shuffle) return;
      playbackMode.value =
          loopMode == LoopMode.one ? PlaybackMode.single : PlaybackMode.loop;
      _schedulePersistPlaybackState();
    });
    _shuffleSub = _player.shuffleModeEnabledStream.listen((enabled) {
      if (enabled) {
        playbackMode.value = PlaybackMode.shuffle;
      } else {
        final loopMode = _player.loopMode;
        playbackMode.value =
            loopMode == LoopMode.one ? PlaybackMode.single : PlaybackMode.loop;
      }
      _schedulePersistPlaybackState();
    });
    try {
      await _restorePlaybackState();
    } finally {
      _restoringState = false;
    }
    _emitSnapshot(force: true);
  }

  Future<void> playQueue(List<SongEntity> songs, int startIndex) async {
    final playable =
        songs.where((s) => (s.uri ?? '').trim().isNotEmpty).toList();
    if (playable.isEmpty) return;
    final targetId = startIndex >= 0 && startIndex < songs.length
        ? songs[startIndex].id
        : null;
    var actualIndex = targetId == null
        ? 0
        : playable.indexWhere((s) => s.id == targetId);
    if (actualIndex < 0) actualIndex = 0;
    queue.value = playable;
    currentIndex.value = actualIndex;
    currentSong.value = playable[actualIndex];
    _maybeProbeSong(playable[actualIndex]);
    _hydrateAndSetCurrentSong(playable[actualIndex]);
    _emitSnapshot(force: true);
    Future<List<AudioSource>> buildSources() async {
      await _proxy.resetSources();
      return Future.wait(playable.map(_sourceForSong));
    }

    Future<bool> setSourcesOnce() async {
      try {
        final sources = await buildSources();
        await _player.setAudioSources(
          sources,
          initialIndex: actualIndex,
        );
        return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('PlayerService.playQueue setAudioSources failed: $e');
        }
        final msg = e.toString();
        final shouldRetry = msg.contains('404') ||
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
          final sources = await buildSources();
          await _player.setAudioSources(
            sources,
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
      final remaining = oldQueue.where((s) => !toRemove.contains(s.id)).toList();
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
    try {
      await _player.stop();
    } catch (_) {}
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
    final playable = songs.where((s) => (s.uri ?? '').trim().isNotEmpty).toList();
    if (playable.isEmpty) {
      await stopAndClear();
      return;
    }
    var actualIndex = startIndex;
    if (actualIndex < 0) actualIndex = 0;
    if (actualIndex >= playable.length) actualIndex = playable.length - 1;

    queue.value = playable;
    currentIndex.value = actualIndex;
    currentSong.value = playable[actualIndex];
    _maybeProbeSong(playable[actualIndex]);
    _emitSnapshot(force: true);

    await _proxy.resetSources();
    final sources = await Future.wait(playable.map(_sourceForSong));
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: actualIndex,
      );
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
        await _player.play();
      } catch (e) {
        await stopAndClear();
        if (kDebugMode) {
          debugPrint('PlayerService._reloadQueue play failed: $e');
        }
      }
    } else {
      try {
        await _player.pause();
      } catch (_) {}
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> play() async {
    if (_player.playing) return;
    await _player.play();
  }

  Future<void> pause() async {
    if (!_player.playing) return;
    await _player.pause();
  }

  Future<void> next() async {
    await _player.seekToNext();
  }

  Future<void> previous() async {
    await _player.seekToPrevious();
  }

  Future<void> seek(Duration position) async {
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
        this.position.value = _player.position;
        _emitSnapshot(force: true);
      }
    }
  }

  Future<void> skipToIndex(int index) async {
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
    await _reloadQueue(
      nextQueue,
      idx,
      play: wasPlaying,
      initialPosition: pos,
    );

    if (playbackMode.value == PlaybackMode.shuffle) {
      await _player.setShuffleModeEnabled(true);
    }
  }

  Future<void> insertNext(List<SongEntity> songs) async {
    final toInsert =
        songs.where((s) => (s.uri ?? '').trim().isNotEmpty).toList();
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
    await _reloadQueue(
      nextQueue,
      idx,
      play: wasPlaying,
      initialPosition: pos,
    );

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
    await _player.setLoopMode(next == PlaybackMode.single ? LoopMode.one : LoopMode.all);
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
        await _player.pause();
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
    sleepTimerDisplayText.value = '$hours:${minutes.toString().padLeft(2, '0')}';
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
    if (last == null || now.difference(last) >= const Duration(milliseconds: 250)) {
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
    snapshot.value = PlaybackSnapshot(
      song: currentSong.value,
      queue: queue.value,
      index: currentIndex.value,
      isPlaying: isPlaying.value,
      position: position.value,
      duration: duration.value,
      bufferedPosition: bufferedPosition.value,
    );
    _schedulePersistPlaybackState();
  }

  Future<void> _restorePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsQueueKey);
    if (raw == null || raw.trim().isEmpty) return;

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
      return;
    }
    if (restoredQueue.isEmpty) return;

    final savedIndex = prefs.getInt(_prefsIndexKey) ?? 0;
    final savedPositionMs = prefs.getInt(_prefsPositionKey) ?? 0;
    final savedMode = prefs.getString(_prefsModeKey);
    final savedSongId = prefs.getString(_prefsSongIdKey);
    final mode = _playbackModeFromString(savedMode) ?? PlaybackMode.loop;
    var actualIndex = savedIndex;
    if (savedSongId != null && savedSongId.isNotEmpty) {
      final idx = restoredQueue.indexWhere((s) => s.id == savedSongId);
      if (idx >= 0) {
        actualIndex = idx;
      }
    }
    if (actualIndex < 0) actualIndex = 0;
    if (actualIndex >= restoredQueue.length) {
      actualIndex = restoredQueue.length - 1;
    }

    // Restore UI state immediately
    queue.value = restoredQueue;
    currentIndex.value = actualIndex;
    currentSong.value = restoredQueue[actualIndex];
    _emitSnapshot(force: true);

    try {
      await _proxy.resetSources();
      // Load audio sources in parallel, but handle errors gracefully
      final sources = await Future.wait(restoredQueue.map((s) async {
        try {
          return await _sourceForSong(s);
        } catch (e) {
          if (kDebugMode) debugPrint('Error restoring source for ${s.title}: $e');
          // Return a placeholder or silent source if loading fails? 
          // For now, let's try to load it anyway or use file source if local
          if (s.isLocal) return AudioSource.file(s.uri ?? '');
          return AudioSource.uri(Uri.parse(s.uri ?? ''));
        }
      }));
      
      await _player.setAudioSources(
        sources,
        initialIndex: actualIndex,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error restoring playback state: $e');
      // Do not clear queue here, as we want to keep the UI state
      // user can try to play again
      return;
    }

    playbackMode.value = mode;
    await _applyPlaybackMode(mode);

    if (savedPositionMs > 0) {
      try {
        await _player.seek(Duration(milliseconds: savedPositionMs));
      } catch (_) {}
    }

    // Always pause on restore, do not auto-play
    try {
      await _player.pause();
    } catch (_) {}
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
    await _player.setLoopMode(mode == PlaybackMode.single ? LoopMode.one : LoopMode.all);
  }

  void _schedulePersistPlaybackState() {
    if (_restoringState) return;
    
    _persistTimer?.cancel();

    // If playing, we need to save periodically to avoid data loss on crash/kill
    if (isPlaying.value) {
      final now = DateTime.now();
      // If > 5s since last save, force save immediately
      if (now.difference(_lastPersistTime) > const Duration(seconds: 5)) {
        _persistPlaybackState();
        return;
      }
      // Otherwise standard debounce
      _persistTimer = Timer(const Duration(milliseconds: 1500), _persistPlaybackState);
    } else {
      // If paused/stopped, save quickly (500ms) to capture state before potential app kill
      _persistTimer = Timer(const Duration(milliseconds: 500), _persistPlaybackState);
    }
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
    await prefs.setInt(_prefsPositionKey, position.value.inMilliseconds);
    await prefs.setString(_prefsModeKey, playbackMode.value.name);
    await prefs.setBool(_prefsWasPlayingKey, isPlaying.value);
    final songId = currentSong.value?.id;
    if (songId == null || songId.isEmpty) {
      await prefs.remove(_prefsSongIdKey);
    } else {
      await prefs.setString(_prefsSongIdKey, songId);
    }
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

  void _maybeProbeSong(SongEntity song) {
    if (song.isLocal) return;
    final uri = (song.uri ?? '').trim();
    if (!uri.startsWith('http')) return;

    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final shouldProbe = !song.tagsParsed || !hasCover || !hasDuration;
    if (!shouldProbe) return;

    final headers = _headersFromSong(song);
    final key = '${song.id}:${hasCover ? 1 : 0}:${hasDuration ? 1 : 0}:${song.tagsParsed ? 1 : 0}';
    if (_probeInflight.containsKey(key)) return;

    final future = _probeAndPersist(song, uri: uri, headers: headers);
    _probeInflight[key] = future;
    future.whenComplete(() => _probeInflight.remove(key));
  }

  void _maybePersistPlaybackDuration(SongEntity song, int durationMs) {
    final existing = song.durationMs ?? 0;
    if (existing > 0) return;
    final prev = _durationPersistedMs[song.id] ?? 0;
    if (prev == durationMs) return;
    _durationPersistedMs[song.id] = durationMs;
    _persistSongUpdate(
      song,
      durationMs: durationMs,
    );
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
    if ((coverPath ?? '').trim().isEmpty && artwork != null && artwork.isNotEmpty) {
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

    final title = (result.title ?? '').trim().isNotEmpty ? result.title!.trim() : null;
    final artist =
        (result.artist ?? '').trim().isNotEmpty ? result.artist!.trim() : null;
    final album = (result.album ?? '').trim().isNotEmpty ? result.album!.trim() : null;
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

  Future<AudioSource> _sourceForSong(SongEntity song) async {
    final rawUri = (song.uri ?? '').trim();
    if (song.isLocal || !rawUri.startsWith('http')) {
      return AudioSource.file(rawUri);
    }
    
    // Resolve URI using safe logic (handles double encoding)
    final remoteUri = _getSafeUri(rawUri);
    // If we couldn't parse it even with fallback, use rawUri for registration
    final finalRemoteUri = remoteUri ?? Uri.parse(rawUri);
    final uriStr = finalRemoteUri.toString();
    
    final headers = _headersFromSong(song);
    final cached = await _audioCache.getCompleteCachedFile(
      uri: uriStr,
      headers: headers,
    );
    if (cached != null) {
      return AudioSource.file(cached.path);
    }

    final cacheFile = await _audioCache.getCacheFile(
      uri: uriStr,
      headers: headers,
    );

    final local = await _proxy.registerSource(
      uri: finalRemoteUri,
      headers: {
        ...?headers,
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': '*/*',
      },
      cacheFile: cacheFile,
    );
    return AudioSource.uri(local);
  }


  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    cancelSleepTimer();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferSub?.cancel();
    await _stateSub?.cancel();
    await _indexSub?.cancel();
    await _loopModeSub?.cancel();
    await _shuffleSub?.cancel();
    await _player.dispose();
  }
}
