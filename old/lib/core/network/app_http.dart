import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'app_error_code.dart';
import 'app_response.dart';
import 'interceptors/index.dart';
import 'response_adapter.dart';

/// App 网络请求核心类
///
/// 1. 统一返回 [AppResponse]，不抛出异常
/// 2. 支持泛型自动解析 [fromJson]
/// 3. 支持配置适配器 [AppResponseAdapter]
/// 4. 支持请求级错误控制 [showError]
class AppHttp {
  static final AppHttp _instance = AppHttp._internal();
  factory AppHttp() => _instance;

  late Dio _dio;
  bool _initialized = false;
  bool _autoShowError = true;

  AppHttp._internal();

  /// 获取 Dio 实例 (懒加载)
  Dio get dio {
    if (!_initialized) {
      // 默认初始化，防止未调用 init 时报错
      init();
    }
    return _dio;
  }

  /// 全局初始化
  ///
  /// [adapter] 响应适配器，默认使用 [DefaultResponseAdapter]
  /// [interceptors] 额外的拦截器
  /// [autoShowError] 是否全局开启错误弹窗，默认 true
  static void init({
    AppResponseAdapter? adapter,
    List<Interceptor>? interceptors,
    bool autoShowError = true,
  }) {
    final instance = AppHttp._instance;
    instance._autoShowError = autoShowError;
    final config = AppConfig.I;

    instance._dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // 1. 添加日志拦截器（完整输出，不截断）
    if (config.enableLog) {
      instance._dio.interceptors.add(
        FullLogInterceptor(
          requestBody: true,
          responseBody: true,
        ),
      );
    }

    // 2. 添加响应处理拦截器 (核心)
    instance._dio.interceptors.add(
      AppResponseInterceptor(
        adapter: adapter ?? DefaultResponseAdapter(),
        autoShowError: autoShowError,
      ),
    );

    // 2.5 添加网络错误拦截器
    instance._dio.interceptors.add(
      NetworkErrorInterceptor(autoShowError: autoShowError),
    );

    // 3. 添加自定义拦截器
    if (interceptors != null) {
      instance._dio.interceptors.addAll(interceptors);
    }

    instance._initialized = true;
  }

  // ========================================================================
  // 核心请求方法 - 统一返回 AppResponse，不抛异常
  // ========================================================================

  /// GET 请求
  ///
  /// [path] 请求路径
  /// [fromJson] 解析函数，将 JSON 转换为对象 T
  /// [showError] 本次请求是否显示错误弹窗，null 则使用全局配置
  Future<AppResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    bool? showError,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      fromJson: fromJson,
      showError: showError,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// POST 请求
  Future<AppResponse<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    bool? showError,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      method: 'POST',
      path: path,
      data: data,
      queryParameters: queryParameters,
      fromJson: fromJson,
      showError: showError,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// PUT 请求
  Future<AppResponse<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    bool? showError,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      method: 'PUT',
      path: path,
      data: data,
      queryParameters: queryParameters,
      fromJson: fromJson,
      showError: showError,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// DELETE 请求
  Future<AppResponse<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    bool? showError,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _request<T>(
      method: 'DELETE',
      path: path,
      data: data,
      queryParameters: queryParameters,
      fromJson: fromJson,
      showError: showError,
      options: options,
      cancelToken: cancelToken,
    );
  }

  // ========================================================================
  // 私有统一请求处理逻辑
  // ========================================================================

  Future<AppResponse<T>> _request<T>({
    required String method,
    required String path,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    bool? showError,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      // 组装 Options
      options ??= Options();
      options.method = method;
      // 将请求级错误控制参数传入 extra
      options.extra ??= {};
      if (showError != null) {
        options.extra!['showError'] = showError;
      }

      final response = await dio.request(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

      // 解析响应 (此时 response.data 已经被拦截器转换为标准 Map)
      return _parseResponse<T>(response.data, fromJson);
    } on DioException catch (e) {
      return _handleDioError<T>(e, showError: showError ?? _autoShowError);
    } catch (e) {
      return AppResponse<T>(
        code: -1,
        msg: '未知错误: ${e.toString()}',
        data: null,
      );
    }
  }

  /// 解析标准响应 Map 为 AppResponse
  AppResponse<T> _parseResponse<T>(
    dynamic data,
    T Function(dynamic)? fromJson,
  ) {
    if (data is Map<String, dynamic>) {
      final code = data['code'] as int;
      final msg = data['msg'] as String;
      final rawData = data['data'];

      // 泛型数据解析
      T? parsedData;
      if (rawData != null && fromJson != null) {
        try {
          parsedData = fromJson(rawData);
        } catch (e) {
          debugPrint('❌ JSON解析失败: $e');
          // 解析失败视为错误，或者你可以决定返回 data=null 但 code=200
          // 这里建议视为错误，因为数据契约不符
          return AppResponse<T>(
            code: AppErrorCode.parseError,
            msg: '数据解析失败: $e',
            originalData: rawData,
          );
        }
      } else if (rawData != null && rawData is T) {
        // 如果未提供解析函数但类型匹配 (例如 T 是 String 或 Map)
        parsedData = rawData;
      }

      return AppResponse<T>(
        code: code,
        msg: msg,
        data: parsedData,
        originalData: rawData,
      );
    }
    return AppResponse<T>(
      code: AppErrorCode.parseError,
      msg: '响应格式错误',
      data: null,
    );
  }

  /// 处理 Dio 错误
  AppResponse<T> _handleDioError<T>(DioException e, {bool showError = true}) {
    String msg = '';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        msg = '连接超时';
        break;
      case DioExceptionType.sendTimeout:
        msg = '请求超时';
        break;
      case DioExceptionType.receiveTimeout:
        msg = '响应超时';
        break;
      case DioExceptionType.badResponse:
        msg = '服务器错误 (${e.response?.statusCode})';
        break;
      case DioExceptionType.cancel:
        msg = '请求取消';
        break;
      default:
        msg = e.message ?? '网络连接异常';
    }

    // 注意：网络错误的弹窗已由 NetworkErrorInterceptor 统一处理
    // 这里只需返回标准的错误响应即可
    return AppResponse<T>(
      code: AppErrorCode.networkError,
      msg: msg,
      data: null,
    );
  }
}
