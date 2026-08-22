import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

/// 一条持久化到 SharedPreferences 的设置项。
///
/// 本身就是 [ValueNotifier]，因此可以直接替换原本的
/// `static final ValueNotifier<T> x = ValueNotifier(default)` 字段，
/// 页面里的 `ValueListenableBuilder` 不需要改动。
///
/// 读写通过 [read] / [write] 两个回调适配 SharedPreferences 的具体类型方法，
/// [sanitize] 用于范围钳制等归一化处理（同时作用于读取和写入）。
class PrefEntry<T> extends ValueNotifier<T> {
  final String key;
  final T defaultValue;
  final T? Function(SharedPreferences prefs, String key) _read;
  final Future<void> Function(SharedPreferences prefs, String key, T value)
  _write;
  final T Function(T value)? sanitize;

  PrefEntry._({
    required this.key,
    required this.defaultValue,
    required T? Function(SharedPreferences, String) read,
    required Future<void> Function(SharedPreferences, String, T) write,
    this.sanitize,
  }) : _read = read,
       _write = write,
       super(sanitize == null ? defaultValue : sanitize(defaultValue));

  static PrefEntry<bool> boolean(String key, {bool defaultValue = false}) {
    return PrefEntry<bool>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getBool(k),
      write: (prefs, k, v) => prefs.setBool(k, v),
    );
  }

  static PrefEntry<int> integer(
    String key, {
    int defaultValue = 0,
    int Function(int value)? sanitize,
  }) {
    return PrefEntry<int>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getInt(k),
      write: (prefs, k, v) => prefs.setInt(k, v),
      sanitize: sanitize,
    );
  }

  static PrefEntry<double> number(
    String key, {
    double defaultValue = 0,
    double Function(double value)? sanitize,
  }) {
    return PrefEntry<double>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getDouble(k),
      write: (prefs, k, v) => prefs.setDouble(k, v),
      sanitize: sanitize,
    );
  }

  static PrefEntry<String> text(String key, {String defaultValue = ''}) {
    return PrefEntry<String>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getString(k),
      write: (prefs, k, v) => prefs.setString(k, v),
    );
  }

  /// 可为空的字符串项：写入 null / 空白串时删除该键，并把内存值归一为 null。
  ///
  /// 归一化放在 [sanitize] 而不是 [write] 里，否则磁盘上删了键、
  /// notifier 却还留着空串，两边状态会不一致。
  static PrefEntry<String?> nullableText(String key) {
    return PrefEntry<String?>._(
      key: key,
      defaultValue: null,
      read: (prefs, k) => prefs.getString(k),
      write: (prefs, k, v) async {
        if (v == null) {
          await prefs.remove(k);
          return;
        }
        await prefs.setString(k, v);
      },
      sanitize: (v) => (v == null || v.trim().isEmpty) ? null : v,
    );
  }

  static PrefEntry<List<String>> stringList(
    String key, {
    required List<String> defaultValue,
    List<String> Function(List<String> value)? sanitize,
  }) {
    return PrefEntry<List<String>>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) => prefs.getStringList(k),
      write: (prefs, k, v) => prefs.setStringList(k, v),
      sanitize: sanitize,
    );
  }

  /// 可为空的颜色项，以 ARGB int 存储；写入 null 时删除该键。
  static PrefEntry<Color?> nullableColor(String key) {
    return PrefEntry<Color?>._(
      key: key,
      defaultValue: null,
      read: (prefs, k) {
        final argb = prefs.getInt(k);
        return argb == null ? null : Color(argb);
      },
      write: (prefs, k, v) async {
        if (v == null) {
          await prefs.remove(k);
          return;
        }
        await prefs.setInt(k, v.toARGB32());
      },
    );
  }

  /// 以枚举名（[Enum.name]）持久化的枚举项，无法识别时回落到 [defaultValue]。
  static PrefEntry<T> enumeration<T extends Enum>(
    String key, {
    required List<T> values,
    required T defaultValue,
  }) {
    return PrefEntry<T>._(
      key: key,
      defaultValue: defaultValue,
      read: (prefs, k) {
        final name = prefs.getString(k);
        if (name == null) return null;
        for (final v in values) {
          if (v.name == name) return v;
        }
        return null;
      },
      write: (prefs, k, v) => prefs.setString(k, v.name),
    );
  }

  T _sanitized(T raw) => sanitize == null ? raw : sanitize!(raw);

  /// 从 [prefs] 读取并写入 [value]（缺省时用 [defaultValue]）。
  void load(SharedPreferences prefs) {
    final raw = _read(prefs, key);
    value = _sanitized(raw ?? defaultValue);
  }

  /// 归一化后持久化并通知监听者。
  Future<void> set(T next) async {
    final prefs = await SharedPreferences.getInstance();
    final sanitized = _sanitized(next);
    await _write(prefs, key, sanitized);
    value = sanitized;
  }
}

/// 一组 [PrefEntry] 的加载入口。
///
/// 替代各 settings 类中重复的 `_loading` / `ensureLoaded` / `_doLoad` 三件套。
class PrefGroup {
  final List<PrefEntry<dynamic>> entries;

  /// 每次加载完成后执行（用于把设置应用到服务层等副作用）。
  final void Function()? onLoaded;

  Future<void>? _loading;

  PrefGroup(this.entries, {this.onLoaded});

  Future<void> ensureLoaded() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in entries) {
      entry.load(prefs);
    }
    onLoaded?.call();
  }

  /// 丢弃已缓存的加载结果，使下次 [ensureLoaded] 重新读取。
  ///
  /// 仅供测试使用。这里没标 `@visibleForTesting`：各 settings 类需要在 lib 侧
  /// 包一层自己的 debug 入口再转调，标注后那层转调会被分析器报警。
  void resetForTest() {
    _loading = null;
  }
}
