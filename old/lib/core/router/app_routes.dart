import 'package:flutter/material.dart';

/// 应用路由配置
///
/// 使用方式：
/// Navigator.pushNamed(context, AppRoutes.home);
/// 或 NavigatorUtil.pushNamed(AppRoutes.home);
class AppRoutes {
  AppRoutes._();

  // 路由常量
  static const String home = '/';
  static const String splash = '/settings';
  static const String egList = '/setting';
  static const String userList = '/user-list';

  // __ROUTE_CONFIG_START__
  /// Material 路由映射
  /// 在 app.dart 中使用: MaterialApp(routes: AppRoutes.routes, ...)
  static Map<String, WidgetBuilder> get routes {
    return {
      // --- 在此下方添加您的自定义路由 ---
    };
  }
  // __ROUTE_CONFIG_END__
}
