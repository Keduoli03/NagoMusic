import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 完整日志拦截器
///
/// 解决 debugPrint 长度限制导致响应内容被截断的问题
class FullLogInterceptor extends Interceptor {
  final bool request;
  final bool requestHeader;
  final bool requestBody;
  final bool responseHeader;
  final bool responseBody;
  final bool error;

  FullLogInterceptor({
    this.request = true,
    this.requestHeader = false,
    this.requestBody = true,
    this.responseHeader = false,
    this.responseBody = true,
    this.error = true,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (request) {
      _log('┌─────────────────────────────────────────────────');
      _log('│ Request: ${options.method} ${options.uri}');
    }
    if (requestHeader) {
      _log('│ Headers: ${options.headers}');
    }
    if (requestBody && options.data != null) {
      _log('│ Body: ${_formatJson(options.data)}');
    }
    if (request) {
      _log('└─────────────────────────────────────────────────');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (responseBody) {
      _log('┌─────────────────────────────────────────────────');
      _log('│ Response: ${response.statusCode} ${response.requestOptions.uri}');
      if (responseHeader) {
        _log('│ Headers: ${response.headers.map}');
      }
      _log('│ Body:');
      _logLongText(_formatJson(response.data));
      _log('└─────────────────────────────────────────────────');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (error) {
      _log('┌─────────────────────────────────────────────────');
      _log('│ ❌ Error: ${err.type}');
      _log('│ Message: ${err.message}');
      if (err.response != null) {
        _log('│ Status: ${err.response?.statusCode}');
        _logLongText(_formatJson(err.response?.data));
      }
      _log('└─────────────────────────────────────────────────');
    }
    handler.next(err);
  }

  /// 格式化 JSON
  String _formatJson(dynamic data) {
    try {
      if (data is Map || data is List) {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
      return data.toString();
    } catch (e) {
      return data.toString();
    }
  }

  /// 输出长文本（分段打印，避免截断）
  void _logLongText(String text) {
    const chunkSize = 800;
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      _log('│ ${text.substring(i, end)}');
    }
  }

  void _log(String msg) {
    debugPrint(msg);
  }
}
