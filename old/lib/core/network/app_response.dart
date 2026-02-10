import 'app_error_code.dart';

/// 统一响应模型
///
/// 无论后端返回什么格式,经过 [AppResponseAdapter] 处理后,
/// 最终在 Service 层拿到的永远是这个对象。
class AppResponse<T> {
  /// 统一状态码
  /// 0 或 200 表示成功,其他表示失败
  final int code;

  /// 统一消息
  /// 成功消息或错误提示
  final String msg;

  /// 业务数据
  final T? data;

  /// 原始响应数据 (保留备查)
  final dynamic originalData;

  AppResponse({
    required this.code,
    required this.msg,
    this.data,
    this.originalData,
  });

  /// 创建成功响应
  factory AppResponse.success({
    T? data,
    String msg = '成功',
    int code = AppErrorCode.success,
  }) {
    return AppResponse(
      code: code,
      msg: msg,
      data: data,
    );
  }

  /// 创建失败响应
  factory AppResponse.fail({
    required String msg,
    int code = AppErrorCode.networkError,
    T? data,
  }) {
    return AppResponse(
      code: code,
      msg: msg,
      data: data,
    );
  }

  // ========================================================================
  // 状态判断方法
  // ========================================================================

  /// 请求是否成功
  bool get isSuccess => code == AppErrorCode.success || code == AppErrorCode.successAlt;

  /// 请求是否失败
  bool get isFailed => !isSuccess;

  /// 是否未授权 (需要登录)
  bool get isUnauthorized => code == AppErrorCode.unauthorized;

  /// 是否禁止访问 (权限不足)
  bool get isForbidden => code == AppErrorCode.forbidden;

  /// 是否网络错误
  bool get isNetworkError => code == AppErrorCode.networkError;

  /// 是否解析错误
  bool get isParseError => code == AppErrorCode.parseError;

  @override
  String toString() {
    return 'AppResponse(code: $code, msg: $msg, data: $data)';
  }
}
