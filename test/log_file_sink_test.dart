import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/log/log_entry.dart';
import 'package:nagomusic/app/services/log/log_file_sink.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nago_log_test');
  });

  tearDown(() async {
    // Windows 上刚 flush 完的日志文件可能还被句柄占着（sink 的写盘是排在
    // 内部 Future 链上的，测试不一定 await 到底），删不掉不是产品问题。
    // 重试几次，仍然失败就算了，别让清理把用例判红。
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  LogFileSink makeSink({int maxBytes = 512 * 1024}) => LogFileSink(
    maxBytes: maxBytes,
    flushDelay: const Duration(milliseconds: 5),
    directoryResolver: () async => temp,
  );

  LogEntry entryAt(int second, {String message = 'hello'}) => LogEntry(
    time: DateTime(2026, 8, 25, 12, 0, second),
    level: LogLevel.error,
    tag: 'Test',
    message: message,
  );

  test('immediate 写入立刻落盘，不等攒批窗口', () async {
    final sink = makeSink();
    sink.write(entryAt(1).toFileString(), immediate: true);

    // 不 await flush，直接把盘上的文件读出来，模拟进程被杀。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final onDisk = await File('${temp.path}/app.log').readAsString();

    expect(onDisk, contains('E/Test: hello'));
  });

  test('写入的内容能完整读回并解析', () async {
    final sink = makeSink();
    for (var i = 0; i < 5; i++) {
      sink.write(entryAt(i, message: '第 $i 条').toFileString());
    }
    await sink.flush();

    final parsed = LogEntry.parseAll(await sink.readAll());
    expect(parsed, hasLength(5));
    expect(parsed.map((e) => e.message), [
      '第 0 条',
      '第 1 条',
      '第 2 条',
      '第 3 条',
      '第 4 条',
    ]);
  });

  test('超过阈值后轮转，旧内容仍然读得到且排在前面', () async {
    final sink = makeSink(maxBytes: 200);

    sink.write(entryAt(1, message: '旧的').toFileString());
    await sink.flush();
    // 把当前文件顶过阈值，下一次写入触发轮转。
    sink.write(entryAt(2, message: 'x' * 300).toFileString());
    await sink.flush();
    sink.write(entryAt(3, message: '新的').toFileString());
    await sink.flush();

    expect(
      await File('${temp.path}/app.log.1').exists(),
      isTrue,
      reason: '应该已经轮转出一个 app.log.1',
    );

    final all = await sink.readAll();
    expect(all.indexOf('旧的'), lessThan(all.indexOf('新的')), reason: '旧的在前');
  });

  test('clear 之后文件和内容都没了', () async {
    final sink = makeSink();
    sink.write(entryAt(1).toFileString());
    await sink.flush();
    expect(await sink.readAll(), isNotEmpty);

    await sink.clear();

    expect(await sink.readAll(), isEmpty);
    expect(await File('${temp.path}/app.log').exists(), isFalse);
  });

  test('readTail 只返回末尾若干行', () async {
    final sink = makeSink();
    for (var i = 0; i < 20; i++) {
      sink.write(entryAt(i, message: '第 $i 条').toFileString());
    }
    await sink.flush();

    final tail = await sink.readTail(maxLines: 5);
    expect(tail, contains('第 19 条'));
    expect(tail, isNot(contains('第 0 条')));
  });
}
