import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../utils/toast_util.dart';
import '../response_adapter.dart';

/// 响应处理拦截器
///
/// 1. 使用适配器转换响应数据
/// 2. 自动处理错误提示 (可配置)
class AppResponseInterceptor extends Interceptor {
  final AppResponseAdapter adapter;
  final bool autoShowError;

  AppResponseInterceptor({
    required this.adapter,
    this.autoShowError = true,
  });

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 1. 转换数据格式
    final adaptedMap = adapter.adapt(response.data);

    // 2. 替换原始数据为标准格式
    response.data = adaptedMap;

    // 3. 自动错误提示处理
    // 优先使用请求配置的 showError,如果未配置则使用全局配置
    final showError =
        response.requestOptions.extra['showError'] as bool? ?? autoShowError;

    final code = adaptedMap['code'];
    final msg = adaptedMap['msg'];

    // 如果失败且需要显示错误
    if (code != 200 && code != 0 && showError == true) {
      ToastUtil.error(msg);
      debugPrint('❌ API错误: $msg');
    }

    handler.next(response);
  }
}
