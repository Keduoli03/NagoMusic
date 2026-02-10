import 'package:dio/dio.dart';

/// Token 自动注入拦截器
///
/// 在每个请求的 Header 中自动添加 Authorization token
///
/// 使用示例:
/// ```dart
/// HttpUtil.init(
///   interceptors: [
///     AuthInterceptor(
///       getToken: () => StorageUtil.getString('token') ?? '',
///     ),
///   ],
/// );
/// ```
class AuthInterceptor extends Interceptor {
  final String Function() getToken;

  AuthInterceptor({required this.getToken});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = getToken();
    if (token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
