import 'package:shared_preferences/shared_preferences.dart';

/// Stores which user-managed music sources are hidden from the library.
///
/// An allow-list would make existing sources disappear after upgrading, so the
/// persisted value is deliberately a deny-list: sources are enabled unless
/// their id is present here.
class SourceVisibilityRepository {
  SourceVisibilityRepository._();

  static final SourceVisibilityRepository instance =
      SourceVisibilityRepository._();

  static const String _prefsKey = 'disabled_source_ids_v1';

  Set<String>? _cache;
  Future<void> _writeTail = Future<void>.value();

  Future<Set<String>> loadDisabledSourceIds() async {
    final cached = _cache;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_prefsKey) ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final result = Set<String>.unmodifiable(ids);
    _cache = result;
    return result;
  }

  Future<bool> isEnabled(String sourceId) async {
    final id = sourceId.trim();
    if (id.isEmpty) return true;
    return !(await loadDisabledSourceIds()).contains(id);
  }

  Future<List<T>> filterEnabled<T>(
    List<T> sources,
    String Function(T source) idOf,
  ) async {
    final disabled = await loadDisabledSourceIds();
    if (disabled.isEmpty) return sources;
    return sources
        .where((source) => !disabled.contains(idOf(source)))
        .toList(growable: false);
  }

  Future<void> setEnabled(String sourceId, bool enabled) {
    final id = sourceId.trim();
    if (id.isEmpty) return Future<void>.value();

    final operation = _writeTail.then((_) => _setEnabledNow(id, enabled));
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<void> _setEnabledNow(String id, bool enabled) async {
    final next = {...await loadDisabledSourceIds()};
    if (enabled) {
      next.remove(id);
    } else {
      next.add(id);
    }

    final ordered = next.toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_prefsKey, ordered);
    if (!saved) throw StateError('Failed to persist source visibility');
    _cache = Set<String>.unmodifiable(next);
  }

  void resetCacheForTest() {
    _cache = null;
    _writeTail = Future<void>.value();
  }
}
