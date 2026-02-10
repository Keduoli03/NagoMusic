import 'app_error_code.dart';

/// 响应数据适配器
///
/// 用于将不同后端接口返回的非标准 JSON 格式,
/// 统一转换为项目标准的 {code, msg, data} 格式。
abstract class AppResponseAdapter {
  Map<String, dynamic> adapt(dynamic json);
}

/// 默认适配器
/// 对应格式: { "code": 200, "msg": "成功", "data": ... }
class DefaultResponseAdapter extends AppResponseAdapter {
  @override
  Map<String, dynamic> adapt(dynamic json) {
    if (json is Map) {
      return {
        'code': json['code'] ?? AppErrorCode.networkError,
        'msg': json['msg'] ?? json['message'] ?? '未知错误',
        'data': json['data'],
      };
    }
    return _buildError('数据格式错误');
  }
}

/// WanAndroid 适配器 (示例)
/// 对应格式: { "errorCode": 0, "errorMsg": "", "data": ... }
class WanAndroidAdapter extends AppResponseAdapter {
  @override
  Map<String, dynamic> adapt(dynamic json) {
    if (json is Map) {
      return {
        'code': json['errorCode'] ?? AppErrorCode.networkError,
        'msg': json['errorMsg'] ?? '',
        'data': json['data'],
      };
    }
    return _buildError('数据格式错误');
  }
}

/// 辅助方法:构建错误数据
Map<String, dynamic> _buildError(String msg) {
  return {
    'code': AppErrorCode.parseError,
    'msg': msg,
    'data': null,
  };
}

/// 图虫 API 适配器
/// 对应格式: { "result": "SUCCESS", "message": "...", "feedList": [...] }
class TuChongAdapter extends AppResponseAdapter {
  @override
  Map<String, dynamic> adapt(dynamic json) {
    if (json is Map) {
      final result = json['result'];
      final isSuccess = result == 'SUCCESS';

      return {
        'code': isSuccess ? 200 : -1,
        'msg': json['message'] ?? '',
        'data': json['feedList'] ?? json['data'],
      };
    }
    return _buildError('数据格式错误');
  }
}
