import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 请求重试拦截器
///
/// 网络错误时自动重试
///
/// 使用示例:
/// ```dart
/// AppHttp.init(
///   interceptors: [
///     RetryInterceptor(
///       dio: AppHttp().dio,
///       maxRetries: 3,
///       retryDelay: const Duration(seconds: 1),
///     ),
///   ],
/// );
/// ```
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration retryDelay;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // 只重试网络相关错误
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    if (retryCount >= maxRetries) {
      debugPrint('❌ 已达最大重试次数 ($maxRetries)');
      return handler.next(err);
    }

    debugPrint('🔄 网络错误,第 ${retryCount + 1} 次重试...');

    // 延迟后重试
    await Future.delayed(retryDelay);

    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      final response = await dio.fetch(err.requestOptions);
      return handler.resolve(response);
    } catch (e) {
      return handler.next(err);
    }
  }

  /// 判断是否应该重试
  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;
  }
}
