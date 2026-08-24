import 'dart:async';

import 'package:flutter/foundation.dart';

/// 睡眠定时器，从 [PlayerService] 里抽出来的自足单元。
///
/// 状态（定时器、到期时间）全部自持，只通过两个 `ValueNotifier` 往外发展示状态、
/// 通过 [onExpire] 回调在到点后让持有者暂停播放 —— 它自己不持有任何播放器引用。
class PlayerSleepTimer {
  /// 到点后的动作。由持有者（PlayerService）绑定为暂停播放。
  final Future<void> Function() onExpire;

  /// 「睡到歌曲结尾」标记，写回 AppPlayerState 上的那个 notifier。
  final ValueNotifier<bool> sleepUntilSongEnd;

  /// 倒计时文本，写回 AppPlayerState 上的那个 notifier。
  final ValueNotifier<String?> sleepTimerDisplayText;

  /// 当前时间来源。默认 [DateTime.now]；测试注入假的时钟，配合 `fakeAsync`
  /// 模拟的定时器一起推进 —— fakeAsync 只模拟定时器、不模拟 `DateTime.now`，
  /// 不注入的话两边时间会错位。
  final DateTime Function() _now;

  PlayerSleepTimer({
    required this.onExpire,
    required this.sleepUntilSongEnd,
    required this.sleepTimerDisplayText,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  Timer? _timer;
  DateTime? _endAt;

  bool get isActive => _timer != null;

  Duration? get remaining {
    final end = _endAt;
    if (end == null) return null;
    return end.difference(_now());
  }

  /// 启动倒计时。会先取消上一次的定时器（顺带重置两个标记），再重开。
  void start(Duration duration, {required bool untilSongEnd}) {
    cancel();
    sleepUntilSongEnd.value = untilSongEnd;
    _endAt = _now().add(duration);
    _updateText();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final end = _endAt;
      if (end == null) return;
      final left = end.difference(_now());
      if (left <= Duration.zero) {
        cancel();
        await onExpire();
        return;
      }
      _updateText();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _endAt = null;
    sleepUntilSongEnd.value = false;
    sleepTimerDisplayText.value = null;
  }

  void _updateText() {
    final end = _endAt;
    if (end == null) {
      sleepTimerDisplayText.value = null;
      return;
    }
    final left = end.difference(_now());
    if (left <= Duration.zero) {
      sleepTimerDisplayText.value = null;
      return;
    }
    final totalMinutes = left.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    sleepTimerDisplayText.value =
        '$hours:${minutes.toString().padLeft(2, '0')}';
  }
}
