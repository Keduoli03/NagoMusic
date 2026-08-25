import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 带轮转的日志文件。
///
/// 之前日志存在 SharedPreferences 里，有两个致命问题：一是每写一条就要把整个
/// 300 条的 `List<String>` 重新序列化写盘；二是崩溃退出时那 500ms 的防抖窗口
/// 里的日志——也就是崩溃现场那几条——必然丢失。
///
/// 这里改成追加写文件：普通日志攒批（[_flushDelay]）后写，警告和异常立即
/// `flush`，保证进程被杀之前已经落盘。
class LogFileSink {
  LogFileSink({
    this.maxBytes = 512 * 1024,
    this.flushDelay = const Duration(seconds: 2),
    Future<Directory> Function()? directoryResolver,
  }) : _resolveDirectory = directoryResolver;

  /// 只为测试留的注入点：不传就落在应用支持目录下的 `logs/`。
  final Future<Directory> Function()? _resolveDirectory;

  /// 单个文件的轮转阈值。超过后 `app.log` 变成 `app.log.1`，重新开一个。
  final int maxBytes;

  /// 普通日志的攒批窗口。
  final Duration flushDelay;

  static const String _fileName = 'app.log';
  static const String _rotatedName = 'app.log.1';

  Directory? _dir;
  Future<Directory>? _dirFuture;
  final StringBuffer _pending = StringBuffer();
  Timer? _flushTimer;

  /// 所有写盘操作串在这条链上，避免并发 append 交错。
  Future<void> _chain = Future<void>.value();

  Future<Directory> _ensureDir() => _dirFuture ??= _openDir();

  Future<Directory> _openDir() async {
    final resolver = _resolveDirectory;
    final dir = resolver != null
        ? await resolver()
        : Directory(
            p.join((await getApplicationSupportDirectory()).path, 'logs'),
          );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  Future<void> ensureReady() async {
    await _ensureDir();
  }

  /// 当前日志文件路径；[ensureReady] 之前返回 null。
  String? get currentPath {
    final dir = _dir;
    return dir == null ? null : p.join(dir.path, _fileName);
  }

  /// 排入一条日志。[immediate] 为 true 时跳过攒批直接落盘。
  void write(String text, {bool immediate = false}) {
    _pending.write(text);
    if (immediate) {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(flush());
      return;
    }
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    if (_pending.isEmpty) return _chain;
    final payload = _pending.toString();
    _pending.clear();
    return _chain = _chain.then((_) => _append(payload));
  }

  Future<void> _append(String payload) async {
    try {
      final dir = await _ensureDir();
      final file = File(p.join(dir.path, _fileName));
      if (await file.exists() && await file.length() > maxBytes) {
        final rotated = File(p.join(dir.path, _rotatedName));
        if (await rotated.exists()) {
          await rotated.delete();
        }
        await file.rename(rotated.path);
      }
      await file.writeAsString(payload, mode: FileMode.append, flush: true);
    } catch (_) {
      // 日志写盘失败不能反过来把 App 弄崩，也不能再记一条日志（会递归）。
    }
  }

  /// 读回全部日志，旧的在前。
  Future<String> readAll() async {
    await flush();
    await _chain;
    final buffer = StringBuffer();
    try {
      final dir = await _ensureDir();
      for (final name in const [_rotatedName, _fileName]) {
        final file = File(p.join(dir.path, name));
        if (await file.exists()) {
          buffer.write(await file.readAsString());
        }
      }
    } catch (_) {
      return buffer.toString();
    }
    return buffer.toString();
  }

  /// 读回最近 [maxLines] 行，用于启动时把上次运行的尾巴恢复到内存里。
  Future<String> readTail({int maxLines = 400}) async {
    final text = await readAll();
    if (text.isEmpty) return text;
    final lines = text.split('\n');
    if (lines.length <= maxLines) return text;
    return lines.sublist(lines.length - maxLines).join('\n');
  }

  Future<void> clear() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _chain = _chain.then((_) async {
      try {
        final dir = await _ensureDir();
        for (final name in const [_rotatedName, _fileName]) {
          final file = File(p.join(dir.path, name));
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (_) {
        // 同上，清不掉就算了。
      }
    });
    await _chain;
  }
}
