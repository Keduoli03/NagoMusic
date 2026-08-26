import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'log/log.dart';

/// 以 JSON 数组形式存放在 SharedPreferences 中的音乐源仓库基类。
///
/// 子类只需提供 prefs key、id 前缀以及 JSON 编解码方式。
abstract class PrefsSourceRepository<T> {
  PrefsSourceRepository();

  static const String _logTag = 'PrefsSourceRepository';

  /// SharedPreferences 中存放该列表的键。
  String get prefsKey;

  /// [newId] 生成的 id 前缀。
  String get idPrefix;

  T fromJson(Map<String, dynamic> json);

  Map<String, dynamic> toJson(T source);

  String idOf(T source);

  /// 上一次 [loadSources] 的结果；写操作（[saveSources] / [upsert] /
  /// [removeById]）会让它失效。
  ///
  /// 播放队列建源（`PlaybackSourceResolver.resolveWebdavRawUri`）每首歌都要问
  /// 一次"这个 sourceId 对应哪个 WebDavSource"，恢复/切歌时一次就是几千次调用。
  /// 没有这层缓存的话，每次都要重新 `jsonDecode` 一遍整份音源列表——音源数量本身
  /// 不多，但乘上几千首歌，解码开销直接摊到了"点一下要等多久"上。
  List<T>? _cache;

  Future<List<T>> loadSources() async {
    final cached = _cache;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _cache = const [];
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
        if (list.isNotEmpty) {
          _cache = list;
          return list;
        }
      }
    } catch (e, s) {
      AppLog.instance.e(_logTag, '解析音乐源列表失败: key=$prefsKey', e, s);
    }
    _cache = const [];
    return const [];
  }

  Future<void> saveSources(List<T> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(sources.map(toJson).toList());
    await prefs.setString(prefsKey, data);
    _cache = List<T>.from(sources);
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

  /// 丢弃内存缓存，使下次 [loadSources] 重新从 prefs 读取。
  ///
  /// 仅供测试使用：`WebDavSourceRepository.instance` / `NavidromeSourceRepository
  /// .instance` 是进程级单例，活过整个测试文件；`setUp` 里 `setMockInitialValues`
  /// 换掉的是 SharedPreferences 的后备存储，换不掉这层缓存，不重置的话下一个测试
  /// 读到的还是上一个测试留下的旧数据。这里没标 `@visibleForTesting`，理由同
  /// `PrefGroup.resetForTest()`。
  void resetCacheForTest() {
    _cache = null;
  }
}
