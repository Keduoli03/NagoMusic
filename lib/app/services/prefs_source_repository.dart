import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'log/log.dart';

/// 以 JSON 数组形式存放在 SharedPreferences 中的音乐源仓库基类。
///
/// 子类只需提供 prefs key、id 前缀以及 JSON 编解码方式。
abstract class PrefsSourceRepository<T> {
  const PrefsSourceRepository();

  static const String _logTag = 'PrefsSourceRepository';

  /// SharedPreferences 中存放该列表的键。
  String get prefsKey;

  /// [newId] 生成的 id 前缀。
  String get idPrefix;

  T fromJson(Map<String, dynamic> json);

  Map<String, dynamic> toJson(T source);

  String idOf(T source);

  Future<List<T>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((e) => fromJson(e.cast<String, dynamic>()))
            .where((e) => idOf(e).trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e, s) {
      AppLog.instance.e(_logTag, '解析音乐源列表失败: key=$prefsKey', e, s);
    }
    return const [];
  }

  Future<void> saveSources(List<T> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(sources.map(toJson).toList());
    await prefs.setString(prefsKey, data);
  }

  Future<void> upsert(T source) async {
    final list = await loadSources();
    final idx = list.indexWhere((e) => idOf(e) == idOf(source));
    final next = [...list];
    if (idx >= 0) {
      next[idx] = source;
    } else {
      next.add(source);
    }
    await saveSources(next);
  }

  Future<void> removeById(String id) async {
    final list = await loadSources();
    final next = list.where((e) => idOf(e) != id).toList();
    await saveSources(next);
  }

  String newId() => '$idPrefix-${DateTime.now().millisecondsSinceEpoch}';
}
