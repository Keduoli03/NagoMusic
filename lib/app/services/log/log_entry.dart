import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 日志级别。声明顺序即严重程度，`index` 可以直接当过滤阈值用。
enum LogLevel {
  debug('D', '调试'),
  info('I', '信息'),
  warn('W', '警告'),
  error('E', '错误');

  const LogLevel(this.code, this.label);

  /// 写进日志文件的单字母标记。
  final String code;

  /// UI 上显示的中文名。
  final String label;

  /// [warn] 及以上无论调试开关是否打开都会被记录。
  bool get isProblem => index >= LogLevel.warn.index;

  static LogLevel? fromCode(String code) {
    for (final level in LogLevel.values) {
      if (level.code == code) return level;
    }
    return null;
  }
}

/// 一条日志。
///
/// [detail] 存异常对象和堆栈（已拍平成多行文本）。UI 默认只显示 [message]，
/// 展开后才显示 [detail]——否则一条崩溃日志会把整个列表撑爆。
@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.detail,
  });

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? detail;

  bool get hasDetail => (detail ?? '').trim().isNotEmpty;

  /// `HH:mm:ss.SSS`，列表里显示用（同一次运行不需要日期）。
  String get clock =>
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}'
      '.${_three(time.millisecond)}';

  /// `yyyy-MM-dd HH:mm:ss.SSS`，写文件用（跨运行需要日期）。
  String get stamp =>
      '${time.year}-${_two(time.month)}-${_two(time.day)} $clock';

  /// 写进日志文件的形式。
  ///
  /// 首行能被 [parseHead] 还原；[detail] 的每一行统一缩进两格，这样堆栈里的
  /// `#0 ...` 不会在读回来的时候被误判成新的一条日志。
  String toFileString() {
    final head = '$stamp ${level.code}/$tag: $message';
    if (!hasDetail) return '$head\n';
    final body = detail!
        .trimRight()
        .split('\n')
        .map((line) => '  $line')
        .join('\n');
    return '$head\n$body\n';
  }

  LogEntry withDetail(String? value) => LogEntry(
    time: time,
    level: level,
    tag: tag,
    message: message,
    detail: value,
  );

  static final RegExp _headPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) '
    r'(\d{2}):(\d{2}):(\d{2})\.(\d{3}) '
    r'([DIWE])/([^:]*): (.*)$',
  );

  /// 从日志文件的一行还原成 [LogEntry]；不是首行（缩进的堆栈行）时返回 null。
  static LogEntry? parseHead(String line) {
    final match = _headPattern.firstMatch(line);
    if (match == null) return null;
    final level = LogLevel.fromCode(match.group(8)!);
    if (level == null) return null;
    return LogEntry(
      time: DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
        int.parse(match.group(7)!),
      ),
      level: level,
      tag: match.group(9)!,
      message: match.group(10)!,
    );
  }

  /// 把一段日志文本解析回条目列表，无法识别的行并进上一条的 [detail]。
  static List<LogEntry> parseAll(String text) {
    final result = <LogEntry>[];
    final detail = StringBuffer();

    void flushDetail() {
      if (result.isEmpty || detail.isEmpty) {
        detail.clear();
        return;
      }
      result[result.length - 1] = result.last.withDetail(
        detail.toString().trimRight(),
      );
      detail.clear();
    }

    for (final line in const LineSplitter().convert(text)) {
      final head = parseHead(line);
      if (head != null) {
        flushDetail();
        result.add(head);
      } else if (line.trim().isNotEmpty) {
        detail.writeln(line.startsWith('  ') ? line.substring(2) : line);
      }
    }
    flushDetail();
    return result;
  }
}

/// 把异常对象和堆栈拍平成 [LogEntry.detail]。
///
/// 堆栈只留前 [stackFrames] 帧——一条完整的 Flutter 堆栈上百行，全存下来会
/// 迅速把日志文件顶到轮转阈值，把真正有用的上下文挤掉。
String? describeError(
  Object? error,
  StackTrace? stack, {
  int stackFrames = 12,
}) {
  if (error == null && stack == null) return null;
  final buffer = StringBuffer();
  if (error != null) {
    buffer.writeln(error.toString().trim());
  }
  final rendered = stack?.toString().trim() ?? '';
  if (rendered.isNotEmpty) {
    final lines = const LineSplitter().convert(rendered);
    final kept = lines.take(stackFrames);
    buffer.writeAll(kept, '\n');
    if (lines.length > stackFrames) {
      buffer.write('\n... 省略 ${lines.length - stackFrames} 帧');
    }
  }
  return buffer.toString().trimRight();
}

String _two(int value) => value.toString().padLeft(2, '0');

String _three(int value) => value.toString().padLeft(3, '0');
