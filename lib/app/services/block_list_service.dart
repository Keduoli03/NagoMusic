import 'package:shared_preferences/shared_preferences.dart';

class BlockListService {
  static final BlockListService instance = BlockListService._();
  BlockListService._();

  Future<Set<String>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key) ?? [];
    return list.toSet();
  }

  Future<void> save(String key, Set<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, items.toList()..sort());
  }

  Future<void> add(String key, String item) async {
    final items = await load(key);
    items.add(item);
    await save(key, items);
  }

  Future<void> remove(String key, String item) async {
    final items = await load(key);
    items.remove(item);
    await save(key, items);
  }
}
