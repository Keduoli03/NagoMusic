import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../utils/toast_util.dart';

/// 网络错误拦截器
///
/// 统一处理超时、连接失败等网络异常，并自动弹出错误提示
///
/// 使用示例:
/// ```dart
/// AppHttp.init(
///   autoShowError: true, // 全局开启错误弹窗
///   interceptors: [
///     // 其他拦截器...
///   ],
/// );
/// ```
class NetworkErrorInterceptor extends Interceptor {
  final bool autoShowError;

  NetworkErrorInterceptor({this.autoShowError = true});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 优先使用请求级配置，如果未设置则使用全局配置
    final showError =
        err.requestOptions.extra['showError'] as bool? ?? autoShowError;

    if (showError) {
      final msg = _getErrorMessage(err);
      ToastUtil.error(msg);
      debugPrint('❌ 网络错误: $msg');
    }

    handler.next(err);
  }

  /// 根据异常类型返回友好的错误提示
  String _getErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时';
      case DioExceptionType.sendTimeout:
        return '请求超时';
      case DioExceptionType.receiveTimeout:
        return '响应超时';
      case DioExceptionType.badResponse:
        return '服务器错误 (${e.response?.statusCode})';
      case DioExceptionType.cancel:
        return '请求取消';
      case DioExceptionType.connectionError:
        return '网络连接异常';
      default:
        return e.message ?? '未知网络错误';
    }
  }
}
