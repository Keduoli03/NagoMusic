import 'package:flutter/material.dart';

// ------------------------------
// 导航工具类 (Material 模式)
// 提供页面跳转、返回等常用导航功能
// ------------------------------
class NavigatorUtil {
  // ------------------------------
  // 1. 静态属性
  // ------------------------------
  /// 私有构造函数
  NavigatorUtil._();

  /// 全局导航键（Material 模式）
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 全局 ScaffoldMessenger 键，用于显示 SnackBar
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// 获取导航状态
  static NavigatorState? get navigator => navigatorKey.currentState;

  /// 获取当前上下文
  static BuildContext? get context => navigatorKey.currentContext;

  // ------------------------------
  // 2. 页面跳转方法
  // ------------------------------
  /// 普通页面跳转
  ///
  /// [page] 目标页面
  /// [replace] 是否替换当前页面
  /// [clearStack] 是否清空导航栈
  static Future<T?> push<T>(
    Widget page, {
    bool replace = false,
    bool clearStack = false,
  }) async {
    final Route<T> route = MaterialPageRoute<T>(
      builder: (BuildContext context) => page,
    );

    if (clearStack) {
      return await navigator?.pushAndRemoveUntil<T>(
        route,
        (Route<dynamic> route) => false,
      );
    } else if (replace) {
      return await navigator?.pushReplacement<T, dynamic>(route);
    } else {
      return await navigator?.push<T>(route);
    }
  }

  /// 带自定义动画的页面跳转
  ///
  /// [page] 目标页面
  /// [transition] 过渡动画构建器
  /// [duration] 动画持续时间
  /// [curve] 动画曲线
  static Future<T?> pushWithAnimation<T>(
    Widget page, {
    required RouteTransitionsBuilder transition,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final Route<T> route = PageRouteBuilder<T>(
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return page;
      },
      transitionDuration: duration,
      transitionsBuilder: transition,
    );

    return await navigator?.push<T>(route);
  }

  /// 命名路由跳转
  ///
  /// [routeName] 路由名称
  /// [arguments] 路由参数
  /// [replace] 是否替换当前页面
  /// [clearStack] 是否清空导航栈
  static Future<T?> pushNamed<T>(
    String routeName, {
    Object? arguments,
    bool replace = false,
    bool clearStack = false,
  }) async {
    if (clearStack) {
      return await navigator?.pushNamedAndRemoveUntil<T>(
        routeName,
        (Route<dynamic> route) => false,
        arguments: arguments,
      );
    } else if (replace) {
      return await navigator?.pushReplacementNamed<T, dynamic>(
        routeName,
        arguments: arguments,
      );
    } else {
      return await navigator?.pushNamed<T>(
        routeName,
        arguments: arguments,
      );
    }
  }

  // ------------------------------
  // 3. 页面返回方法
  // ------------------------------
  /// 返回上一页
  ///
  /// [result] 返回结果
  static void pop<T>([T? result]) {
    if (navigator?.canPop() ?? false) {
      navigator?.pop<T>(result);
    }
  }

  /// 返回上一页，如果键盘弹起则先关闭键盘
  static void popWithKeyboardCheck<T>([T? result]) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      pop<T>(result);
      return;
    }

    final hasFocus = FocusScope.of(context).hasFocus;
    if (hasFocus) {
      FocusScope.of(context).unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 400), () {
          pop<T>(result);
        });
      });
    } else {
      pop<T>(result);
    }
  }

  /// 检查是否可以返回
  static bool canPop() {
    return navigator?.canPop() ?? false;
  }

  /// 返回到指定页面
  ///
  /// [routeName] 目标路由名称
  static void popUntil(String routeName) {
    navigator?.popUntil(ModalRoute.withName(routeName));
  }

  /// 返回到根页面
  static void popToRoot() {
    navigator?.popUntil((route) => route.isFirst);
  }

  // ------------------------------
  // 4. 路由参数处理方法
  // ------------------------------
  /// 获取路由传递的参数
  static T? getArguments<T>([T? defaultValue]) {
    final context = navigatorKey.currentContext;
    if (context == null) return defaultValue;

    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route == null) return defaultValue;

    final args = route.settings.arguments;
    if (args == null) return defaultValue;

    try {
      if (args is T) {
        return args as T;
      } else {
        debugPrint('路由参数类型不匹配: 期望 ${T.toString()}, 实际 ${args.runtimeType}');
        return defaultValue;
      }
    } catch (e) {
      debugPrint('获取路由参数异常: $e');
      return defaultValue;
    }
  }
}
