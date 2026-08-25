import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log_entry.dart';
import 'log_file_sink.dart';

/// 全 App 的日志入口。
///
/// 和旧的 `DebugLogService` 相比有三处行为差异，都是刻意的：
///
/// 1. **异常无视开关**。[LogLevel.warn] 及以上永远记录、永远落盘，不管用户有
///    没有打开「调试模式」。旧实现在 `add()` 开头 `if (!enabled) return`，
///    等于出问题的那一刻恰好什么都没记——日志最该起作用的场景反而是空的。
/// 2. **不再受 `kDebugMode` 限制**。旧的 `_debugLog()` 全都写成
///    `if (!kDebugMode) return`，release 包里一条都不写。而用户手上跑的正是
///    release 包。现在 `kDebugMode` 只决定要不要往控制台镜像一份。
/// 3. **落盘到文件而不是 SharedPreferences**，细节见 [LogFileSink]。
class AppLog {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 沿用旧 key，老用户升级后开关状态不会被重置。
  static const String _prefsVerbose = 'debug_log_enabled';

  /// 旧版本把日志正文塞在这个 key 里，加载时顺手清掉。
  static const String _legacyPrefsEntries = 'debug_log_entries';

  static const int _maxEntries = 600;

  /// 「调试模式」开关。只影响 [LogLevel.debug] / [LogLevel.info]。
  final ValueNotifier<bool> verbose = ValueNotifier(false);

  /// 内存中的日志，时间升序（最新在末尾）。
  final ValueNotifier<List<LogEntry>> entries = ValueNotifier(
    const <LogEntry>[],
  );

  final LogFileSink _sink = LogFileSink();

  Future<void>? _loading;
  bool _ready = false;
  bool _hookInstalled = false;

  /// [ensureLoaded] 完成前产生的日志。启动早期的异常正是最值得留下的，
  /// 不能因为 SharedPreferences 还没读完就丢掉。
  final List<LogEntry> _pending = <LogEntry>[];

  /// 安装 debugPrint 钩子之前的原始实现。镜像到控制台必须走它，否则
  /// 「写日志 → debugPrint → 钩子 → 写日志」会无限递归。
  DebugPrintCallback _console = debugPrint;

  String? get logFilePath => _sink.currentPath;

  // ------------------------------------------------------------------ 写入

  void d(String tag, String message) => _record(LogLevel.debug, tag, message);

  void i(String tag, String message) => _record(LogLevel.info, tag, message);

  void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      _record(LogLevel.warn, tag, message, error, stack);

  void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      _record(LogLevel.error, tag, message, error, stack);

  void _record(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    // 这里是唯一的过滤点：问题级别一律放行，其余看开关。
    if (!level.isProblem && !verbose.value) return;

    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: _sanitizeTag(tag),
      message: message.trim(),
      detail: describeError(error, stack),
    );

    if (kDebugMode) {
      _console('${entry.level.code}/${entry.tag}: ${entry.message}');
      if (entry.hasDetail) _console(entry.detail!);
    }

    if (!_ready) {
      _pending.add(entry);
      if (_pending.length > _maxEntries) _pending.removeAt(0);
      return;
    }
    _commit(entry);
  }

  void _commit(LogEntry entry) {
    final next = <LogEntry>[...entries.value, entry];
    if (next.length > _maxEntries) {
      next.removeRange(0, next.length - _maxEntries);
    }
    entries.value = next;
    // 问题级别立即 flush：进程被系统杀掉时，攒批窗口里的内容就是崩溃现场。
    _sink.write(entry.toFileString(), immediate: entry.level.isProblem);
  }

  // ------------------------------------------------------------------ 生命周期

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    await _sink.ensureReady();

    final prefs = await SharedPreferences.getInstance();
    verbose.value = prefs.getBool(_prefsVerbose) ?? false;
    if (prefs.containsKey(_legacyPrefsEntries)) {
      await prefs.remove(_legacyPrefsEntries);
    }

    // 把上次运行的尾巴读回来，这样「上次崩溃了」在重启后仍然看得到。
    List<LogEntry> history = const <LogEntry>[];
    try {
      history = LogEntry.parseAll(await _sink.readTail());
    } catch (_) {
      history = const <LogEntry>[];
    }

    final combined = <LogEntry>[...history, ..._pending];
    if (combined.length > _maxEntries) {
      combined.removeRange(0, combined.length - _maxEntries);
    }
    entries.value = combined;

    // _pending 里的条目还没落过盘，补写进去。
    for (final entry in _pending) {
      _sink.write(entry.toFileString());
    }
    _pending.clear();
    _ready = true;

    _installDebugPrintHook();
    _record(LogLevel.info, 'App', '=== 新会话开始 ===');
    // 会话分隔线要能在崩溃日志里看到，所以强制落盘一次。
    unawaited(_sink.flush());
  }

  Future<void> setVerbose(bool value) async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsVerbose, value);
    verbose.value = value;
    // 关的时候也记一条，否则日志会在无解释的情况下突然断掉。
    _record(
      LogLevel.info,
      'App',
      value ? '调试模式已开启，开始记录每一步操作' : '调试模式已关闭，此后只记录警告和异常',
    );
    unawaited(_sink.flush());
  }

  Future<void> clear() async {
    await ensureLoaded();
    entries.value = const <LogEntry>[];
    await _sink.clear();
  }

  /// 导出全文：优先用文件里的内容（含上一次运行），文件读不到时退回内存。
  Future<String> exportText() async {
    await ensureLoaded();
    final text = await _sink.readAll();
    if (text.trim().isNotEmpty) return text;
    if (entries.value.isEmpty) return '暂无日志。';
    return entries.value.map((entry) => entry.toFileString()).join();
  }

  Future<void> flush() => _sink.flush();

  // ------------------------------------------------------------------ 钩子

  /// 把散落在各处的裸 `debugPrint(...)` 也收进日志里。
  ///
  /// 这些调用本身没有级别信息，统一按 [LogLevel.debug] 处理；形如
  /// `[PlayerService] xxx` 的前缀会被提取成 tag。
  void _installDebugPrintHook() {
    if (_hookInstalled) return;
    _hookInstalled = true;
    _console = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _console(message, wrapWidth: wrapWidth);
      if (message == null || message.isEmpty) return;
      if (!verbose.value || !_ready) return;
      final match = _bracketTag.firstMatch(message);
      _commit(
        LogEntry(
          time: DateTime.now(),
          level: LogLevel.debug,
          tag: _sanitizeTag(match?.group(1) ?? 'print'),
          message: (match?.group(2) ?? message).trim(),
        ),
      );
    };
  }

  static final RegExp _bracketTag = RegExp(r'^\[([^\]]{1,32})\]\s*(.*)$');

  /// tag 里不能有 `:` 和换行，否则写进文件后 [LogEntry.parseHead] 会解析错位。
  static String _sanitizeTag(String tag) {
    final cleaned = tag.replaceAll(RegExp(r'[:\r\n]'), '').trim();
    return cleaned.isEmpty ? 'app' : cleaned;
  }
}
