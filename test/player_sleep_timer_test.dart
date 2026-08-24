import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/player/player_sleep_timer.dart';

void main() {
  group('PlayerSleepTimer', () {
    late ValueNotifier<bool> untilSongEnd;
    late ValueNotifier<String?> displayText;
    late int expireCount;
    late DateTime now;
    late PlayerSleepTimer timer;

    /// fakeAsync 只模拟定时器、不模拟 DateTime.now，所以测试注入一个假的时钟
    /// 并和 fakeAsync 一起推进，两边才对齐。
    setUp(() {
      untilSongEnd = ValueNotifier(false);
      displayText = ValueNotifier(null);
      expireCount = 0;
      now = DateTime(2026, 1, 1, 12, 0, 0);
      timer = PlayerSleepTimer(
        onExpire: () async => expireCount++,
        sleepUntilSongEnd: untilSongEnd,
        sleepTimerDisplayText: displayText,
        now: () => now,
      );
    });

    test('启动后 isActive，倒计时文本随时间递减', () {
      fakeAsync((async) {
        timer.start(const Duration(minutes: 5), untilSongEnd: false);
        expect(timer.isActive, isTrue);
        expect(untilSongEnd.value, isFalse);
        // 格式是「小时:分钟」：5 分钟 = 0 小时 5 分 → 0:05（照搬原实现）。
        expect(displayText.value, '0:05');

        // 推进假时钟和假时间各 1 分钟，再让定时器 tick 一次去重算文本。
        now = now.add(const Duration(minutes: 1));
        async.elapse(const Duration(seconds: 1));
        expect(displayText.value, '0:04');

        // 推到 5 分钟后：到点，回调触发、状态复位、文本清空。
        now = now.add(const Duration(minutes: 4));
        async.elapse(const Duration(seconds: 1));
        expect(expireCount, 1);
        expect(timer.isActive, isFalse);
        expect(displayText.value, isNull);
        expect(untilSongEnd.value, isFalse);
      });
    });

    test('untilSongEnd 标记被正确写入和复位', () {
      fakeAsync((async) {
        timer.start(const Duration(seconds: 10), untilSongEnd: true);
        expect(untilSongEnd.value, isTrue);

        timer.cancel();
        expect(untilSongEnd.value, isFalse);
        expect(timer.isActive, isFalse);
        expect(displayText.value, isNull);
      });
    });

    test('cancel 后到点不再触发回调', () {
      fakeAsync((async) {
        timer.start(const Duration(seconds: 5), untilSongEnd: false);
        timer.cancel();
        now = now.add(const Duration(minutes: 1));
        async.elapse(const Duration(seconds: 2));
        expect(expireCount, 0);
      });
    });

    test('再次 start 会先取消上一次的定时器', () {
      fakeAsync((async) {
        timer.start(const Duration(seconds: 10), untilSongEnd: false);
        timer.start(const Duration(seconds: 20), untilSongEnd: true);
        now = now.add(const Duration(seconds: 12));
        async.elapse(const Duration(seconds: 1));
        // 第一次的 10 秒早该到期，但被第二次 start 取消了，不该触发。
        expect(expireCount, 0);
        now = now.add(const Duration(seconds: 9));
        async.elapse(const Duration(seconds: 1));
        expect(expireCount, 1);
      });
    });

    test('remaining 反映剩余时间', () {
      fakeAsync((async) {
        timer.start(const Duration(minutes: 2), untilSongEnd: false);
        now = now.add(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 1));
        expect(timer.remaining, const Duration(minutes: 1, seconds: 30));
        timer.cancel();
        expect(timer.remaining, isNull);
      });
    });
  });
}
