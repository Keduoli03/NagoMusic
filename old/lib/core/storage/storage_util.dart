import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储工具
///
/// 封装 SharedPreferences，提供类型安全的存取方法
///
/// 使用示例：
/// ```dart
/// // 存储
/// await StorageUtil.setString('username', 'john');
/// await StorageUtil.setBool('isVip', true);
///
/// // 读取
/// final username = StorageUtil.getString('username');
/// final isVip = StorageUtil.getBool('isVip', defaultValue: false);
/// ```
class StorageUtil {
  static SharedPreferences? _prefs;

  /// 初始化（必须在使用前调用）
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _instance {
    if (_prefs == null) {
      throw StateError('StorageUtil 未初始化，请先调用 StorageUtil.init()');
    }
    return _prefs!;
  }

  /// 是否已初始化
  static bool get isInitialized => _prefs != null;

  // ==================== String ====================

  static Future<bool> setString(String key, String value) =>
      _instance.setString(key, value);

  static String? getString(String key) => _instance.getString(key);

  static String getStringOrDefault(String key, {String defaultValue = ''}) =>
      _instance.getString(key) ?? defaultValue;

  // ==================== Int ====================

  static Future<bool> setInt(String key, int value) =>
      _instance.setInt(key, value);

  static int? getInt(String key) => _instance.getInt(key);

  static int getIntOrDefault(String key, {int defaultValue = 0}) =>
      _instance.getInt(key) ?? defaultValue;

  // ==================== Double ====================

  static Future<bool> setDouble(String key, double value) =>
      _instance.setDouble(key, value);

  static double? getDouble(String key) => _instance.getDouble(key);

  static double getDoubleOrDefault(String key, {double defaultValue = 0.0}) =>
      _instance.getDouble(key) ?? defaultValue;

  // ==================== Bool ====================

  static Future<bool> setBool(String key, bool value) =>
      _instance.setBool(key, value);

  static bool? getBool(String key) => _instance.getBool(key);

  static bool getBoolOrDefault(String key, {bool defaultValue = false}) =>
      _instance.getBool(key) ?? defaultValue;

  // ==================== StringList ====================

  static Future<bool> setStringList(String key, List<String> value) =>
      _instance.setStringList(key, value);

  static List<String>? getStringList(String key) =>
      _instance.getStringList(key);

  static List<String> getStringListOrDefault(
    String key, {
    List<String> defaultValue = const [],
  }) =>
      _instance.getStringList(key) ?? defaultValue;

  // ==================== 通用操作 ====================

  /// 删除指定键
  static Future<bool> remove(String key) => _instance.remove(key);

  /// 清空所有数据
  static Future<bool> clear() => _instance.clear();

  /// 是否包含指定键
  static bool containsKey(String key) => _instance.containsKey(key);

  /// 获取所有键
  static Set<String> getKeys() => _instance.getKeys();
}
