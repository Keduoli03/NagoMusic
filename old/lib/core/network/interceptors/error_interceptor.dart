import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 统一错误处理拦截器
///
/// 处理 401/403 等常见错误状态码
///
/// 使用示例:
/// ```dart
/// HttpUtil.init(
///   interceptors: [
///     ErrorInterceptor(
///       onUnauthorized: (_) {
///         // 跳转登录页
///         Get.offAllNamed('/login');
///       },
///       onForbidden: (_) {
///         // 显示无权限提示
///         showToast('无访问权限');
///       },
///     ),
///   ],
/// );
/// ```
class ErrorInterceptor extends Interceptor {
  final void Function(int statusCode)? onUnauthorized;
  final void Function(int statusCode)? onForbidden;

  ErrorInterceptor({
    this.onUnauthorized,
    this.onForbidden,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;

    if (statusCode == 401) {
      debugPrint('❌ 未授权访问,请重新登录');
      onUnauthorized?.call(401);
    } else if (statusCode == 403) {
      debugPrint('❌ 无访问权限');
      onForbidden?.call(403);
    }

    handler.next(err);
  }
}
