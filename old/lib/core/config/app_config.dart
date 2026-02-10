import 'package:flutter/foundation.dart';

import '../storage/storage_keys.dart';
import '../storage/storage_util.dart';

/// 应用常量
class AppConstants {
  AppConstants._();

  static const String appName = 'Vibe音乐';
  static const String appVersion = '1.0.0';

  /// 免责声明
  static const String disclaimer =
      '本应用仅供学习交流使用，API 数据由第三方提供，本应用不保证数据的准确性、完整性及安全性。如有侵权，请联系删除。';

  /// 国内可直接访问的 API 地址 (示例使用 图虫API)
  static const String apiBaseUrl = 'https://api.tuchong.com';

  static const int apiTimeout = 30000;
  static const int pageSize = 20;
}

/// 应用配置
///
/// 统一管理应用配置和生命周期状态
///
/// 使用示例：
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AppConfig.init();
///   runApp(const App());
/// }
/// ```
class AppConfig {
  static AppConfig? _instance;
  static AppConfig get I => _instance!;

  // ==================== 配置 ====================

  /// API 基础地址
  final String apiBaseUrl;

  /// 连接超时时间
  final Duration connectTimeout;

  /// 接收超时时间
  final Duration receiveTimeout;

  /// 是否启用日志
  final bool enableLog;

  /// 是否使用 Mock 数据 (用于网络示例演示)
  final bool useMockData;

  // ==================== 生命周期状态 ====================

  /// 是否首次启动
  final bool isFirstLaunch;

  /// 是否更新后首次启动
  final bool isFirstLaunchAfterUpdate;

  /// 当前版本号
  final String currentVersion;

  /// 上一个版本号
  final String previousVersion;

  AppConfig._({
    required this.apiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.enableLog,
    required this.useMockData,
    required this.isFirstLaunch,
    required this.isFirstLaunchAfterUpdate,
    required this.currentVersion,
    required this.previousVersion,
  });

  /// 初始化应用配置
  ///
  /// 必须在应用启动时调用（runApp 之前）
  static Future<void> init({
    String? apiBaseUrl,
    Duration connectTimeout =
        const Duration(milliseconds: AppConstants.apiTimeout),
    Duration receiveTimeout =
        const Duration(milliseconds: AppConstants.apiTimeout),
    bool? enableLog,
    bool useMockData = false,
  }) async {
    // 1. 初始化存储
    await StorageUtil.init();

    // 2. 获取版本信息
    const currentVersion = AppConstants.appVersion;
    final previousVersion = StorageUtil.getString(StorageKeys.appVersion) ?? '';

    // 3. 判断启动状态
    final isFirstLaunch = !StorageUtil.containsKey(StorageKeys.isFirstLaunch);
    final isFirstLaunchAfterUpdate =
        previousVersion.isNotEmpty && previousVersion != currentVersion;

    // 4. 更新存储
    if (isFirstLaunch) {
      await StorageUtil.setBool(StorageKeys.isFirstLaunch, false);
    }
    await StorageUtil.setString(StorageKeys.appVersion, currentVersion);

    // 5. 创建实例
    _instance = AppConfig._(
      apiBaseUrl: apiBaseUrl ?? AppConstants.apiBaseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      enableLog: enableLog ?? kDebugMode,
      useMockData: useMockData,
      isFirstLaunch: isFirstLaunch,
      isFirstLaunchAfterUpdate: isFirstLaunchAfterUpdate,
      currentVersion: currentVersion,
      previousVersion: previousVersion,
    );

    _printInitLog();
  }

  static void _printInitLog() {
    if (!_instance!.enableLog) return;
    debugPrint('┌─────────────────────────────────────');
    debugPrint('│ AppConfig 初始化完成');
    debugPrint('│ API: ${_instance!.apiBaseUrl}');
    debugPrint('│ 版本: ${_instance!.currentVersion}');
    debugPrint('│ 首次启动: ${_instance!.isFirstLaunch}');
    debugPrint('│ 更新后首次: ${_instance!.isFirstLaunchAfterUpdate}');
    debugPrint('└─────────────────────────────────────');
  }

  /// 是否已初始化
  static bool get isInitialized => _instance != null;
}
