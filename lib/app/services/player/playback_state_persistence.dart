import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../state/player_state.dart';
import '../../state/song_state.dart';
import '../log/log.dart';

/// 播放状态持久化的**序列化一半**，从 [PlayerService] 里抽出来。
///
/// 只负责「读 prefs → 还原出 [PlaybackRestoreState]」和「当前播放状态 → 写
/// prefs」，外加防抖调度。**应用的另一半留在 PlayerService**：拿到 restore
/// session 之后写回队列 / currentSong、预载音频源、seek、清会话这些操作
/// 直接碰 `_player` 和 `_restoreSession` 的互锁 —— 把读取侧和应用侧劈开，
/// 正好会丢用户的续播位置。
///
/// 读当前播放状态全部通过回调注入（归 PlayerService / AppPlayerState 所有），
/// 这里只持有自己的防抖定时器和 `_lastPersistTime`。
class PlaybackStatePersistence {
  static const String _logTag = 'PlaybackStatePersistence';

  static const String prefsQueueKey = 'playback_queue_v1';
  static const String prefsIndexKey = 'playback_index_v1';
  static const String prefsPositionKey = 'playback_position_v1';
  static const String prefsModeKey = 'playback_mode_v1';
  static const String prefsWasPlayingKey = 'playback_was_playing_v1';
  static const String prefsSongIdKey = 'playback_song_id_v1';

  static const Duration _playingPersistInterval = Duration(seconds: 1);
  static const Duration _idlePersistDelay = Duration(milliseconds: 200);

  /// 正在恢复会话（恢复期间不落盘，避免把中间态写进去）。
  final bool Function() isRestoring;

  final bool Function() isPlaying;
  final List<SongEntity> Function() queue;
  final int Function() currentIndex;
  final PlaybackMode Function() mode;
  final String? Function() currentSongId;

  /// 待持久化的位置。含恢复会话的 `protectPosition` 保护逻辑，由持有者提供 ——
  /// 它读 `_restoreSession` 和 `_player.position`，这两个都归 PlayerService。
  final Duration Function() positionForPersistence;

  Timer? _persistTimer;
  DateTime _lastPersistTime = DateTime.fromMillisecondsSinceEpoch(0);

  PlaybackStatePersistence({
    required this.isRestoring,
    required this.isPlaying,
    required this.queue,
    required this.currentIndex,
    required this.mode,
    required this.currentSongId,
    required this.positionForPersistence,
  });

  /// 调度一次持久化：播放中按 1 秒节流，空闲 200ms 防抖，恢复会话期间跳过。
  void schedule({bool immediate = false}) {
    if (isRestoring()) return;

    if (immediate) {
      _persistTimer?.cancel();
      _persistTimer = null;
      unawaited(persistNow());
      return;
    }

    if (isPlaying()) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastPersistTime);
      if (elapsed >= _playingPersistInterval) {
        _persistTimer?.cancel();
        _persistTimer = null;
        unawaited(persistNow());
        return;
      }

      if (_persistTimer != null && _persistTimer!.isActive) return;
      _persistTimer = Timer(_playingPersistInterval - elapsed, () {
        _persistTimer = null;
        unawaited(persistNow());
      });
      return;
    }

    _persistTimer?.cancel();
    _persistTimer = Timer(_idlePersistDelay, () {
      _persistTimer = null;
      unawaited(persistNow());
    });
  }

  void cancelTimer() {
    _persistTimer?.cancel();
    _persistTimer = null;
  }

  Future<void> persistNow() async {
    cancelTimer();
    await persist();
  }

  Future<void> persist() async {
    _lastPersistTime = DateTime.now();
    final list = queue();
    if (list.isEmpty || currentIndex() < 0) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final serialized = jsonEncode(list.map((e) => e.toMap()).toList());
    await prefs.setString(prefsQueueKey, serialized);
    await prefs.setInt(prefsIndexKey, currentIndex());
    await prefs.setInt(
      prefsPositionKey,
      positionForPersistence().inMilliseconds,
    );
    await prefs.setString(prefsModeKey, mode().name);
    await prefs.setBool(prefsWasPlayingKey, isPlaying());
    final songId = currentSongId();
    if (songId == null || songId.isEmpty) {
      await prefs.remove(prefsSongIdKey);
    } else {
      await prefs.setString(prefsSongIdKey, songId);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsQueueKey);
    await prefs.remove(prefsIndexKey);
    await prefs.remove(prefsPositionKey);
    await prefs.remove(prefsModeKey);
    await prefs.remove(prefsWasPlayingKey);
    await prefs.remove(prefsSongIdKey);
  }

  /// 从 prefs 还原出上次的播放会话；没有或损坏返回 null。
  Future<PlaybackRestoreState?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsQueueKey);
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '解析上次播放队列 JSON 失败，放弃恢复播放状态', e, s);
      return null;
    }
    if (restoredQueue.isEmpty) return null;

    final savedIndex = prefs.getInt(prefsIndexKey) ?? 0;
    final savedPositionMs = prefs.getInt(prefsPositionKey) ?? 0;
    final savedMode = prefs.getString(prefsModeKey);
    final savedSongId = prefs.getString(prefsSongIdKey);
    final mode = modeFromString(savedMode) ?? PlaybackMode.loop;
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
    return PlaybackRestoreState(
      queue: restoredQueue,
      index: actualIndex,
      songId: songId,
      position: Duration(
        milliseconds: savedPositionMs < 0 ? 0 : savedPositionMs,
      ),
      mode: mode,
      wasPlaying: prefs.getBool(prefsWasPlayingKey) ?? false,
    );
  }

  PlaybackMode? modeFromString(String? value) {
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
}

/// 一次要恢复的播放会话。
///
/// `sourcePrepared` / `seekApplied` / `prepareFailed` 是恢复过程中的互锁标记，
/// 由 PlayerService 的 apply 一侧（`_prepareRestoredAudioSource` /
/// `_ensureRestoredPlaybackReady` / `_completeRestoreSessionIfReady`）读写。
class PlaybackRestoreState {
  final List<SongEntity> queue;
  final int index;
  final String songId;
  final Duration position;
  final PlaybackMode mode;
  final bool wasPlaying;
  bool sourcePrepared;
  bool seekApplied;
  bool prepareFailed;

  PlaybackRestoreState({
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
