import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/log/log_entry.dart';

void main() {
  group('LogEntry 文件格式', () {
    test('单行日志能原样写出并解析回来', () {
      final entry = LogEntry(
        time: DateTime(2026, 8, 25, 13, 4, 5, 67),
        level: LogLevel.info,
        tag: 'PlayerService',
        message: 'startPlayback song=Ave Maria',
      );

      expect(
        entry.toFileString(),
        '2026-08-25 13:04:05.067 I/PlayerService: '
        'startPlayback song=Ave Maria\n',
      );

      final parsed = LogEntry.parseAll(entry.toFileString());
      expect(parsed, hasLength(1));
      expect(parsed.single.time, entry.time);
      expect(parsed.single.level, LogLevel.info);
      expect(parsed.single.tag, 'PlayerService');
      expect(parsed.single.message, entry.message);
    });

    test('消息里的冒号不会被误当成 tag 分隔符', () {
      final entry = LogEntry(
        time: DateTime(2026, 8, 25, 1, 2, 3, 4),
        level: LogLevel.error,
        tag: 'WebDav',
        message: 'GET https://host:8443/a.flac 失败: 404',
      );
      final parsed = LogEntry.parseAll(entry.toFileString()).single;
      expect(parsed.tag, 'WebDav');
      expect(parsed.message, 'GET https://host:8443/a.flac 失败: 404');
    });

    test('堆栈缩进后不会被当成新的日志条目', () {
      final entry = LogEntry(
        time: DateTime(2026, 8, 25, 10, 0, 0, 0),
        level: LogLevel.error,
        tag: 'Zone',
        message: '未捕获的异常',
        detail:
            'Bad state: boom\n#0      main (file:///a.dart:1:2)\n'
            '#1      _run (file:///b.dart:3:4)',
      );

      final parsed = LogEntry.parseAll(entry.toFileString());
      expect(parsed, hasLength(1), reason: '堆栈行不该被解析成独立条目');
      expect(parsed.single.detail, contains('#0      main'));
      expect(parsed.single.detail, contains('#1      _run'));
    });

    test('多条日志按顺序解析，堆栈归属前一条', () {
      final first = LogEntry(
        time: DateTime(2026, 8, 25, 10, 0, 0, 0),
        level: LogLevel.error,
        tag: 'A',
        message: '炸了',
        detail: 'Exception: x\n#0      f (file:///a.dart:1:1)',
      );
      final second = LogEntry(
        time: DateTime(2026, 8, 25, 10, 0, 1, 0),
        level: LogLevel.debug,
        tag: 'B',
        message: '继续',
      );

      final parsed = LogEntry.parseAll(
        first.toFileString() + second.toFileString(),
      );
      expect(parsed.map((e) => e.tag), ['A', 'B']);
      expect(parsed.first.hasDetail, isTrue);
      expect(parsed.last.hasDetail, isFalse);
    });
  });

  group('LogLevel', () {
    test('warn 及以上算问题级别（不受调试开关限制）', () {
      expect(LogLevel.debug.isProblem, isFalse);
      expect(LogLevel.info.isProblem, isFalse);
      expect(LogLevel.warn.isProblem, isTrue);
      expect(LogLevel.error.isProblem, isTrue);
    });
  });

  group('describeError', () {
    test('没有异常也没有堆栈时返回 null', () {
      expect(describeError(null, null), isNull);
    });

    test('堆栈超长时截断并标注省略帧数', () {
      final stack = StackTrace.fromString(
        List.generate(
          30,
          (i) => '#$i      frame$i (file:///a.dart:$i:1)',
        ).join('\n'),
      );
      final detail = describeError(StateError('boom'), stack, stackFrames: 5);

      expect(detail, contains('boom'));
      expect(detail, contains('#4      frame4'));
      expect(detail, isNot(contains('#5      frame5')));
      expect(detail, contains('省略 25 帧'));
    });
  });
}
