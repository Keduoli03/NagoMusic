# AppNetwork 网络层

基于 Dio 封装的企业级 Flutter 网络请求方案。

---

## 目录结构

```
lib/core/network/
├── app_error_code.dart               # 统一错误码常量
├── app_http.dart                     # 核心请求类 (单例)
├── app_response.dart                 # 统一响应模型
├── response_adapter.dart             # 响应适配器 (格式转换)
├── index.dart                        # 统一导出
└── interceptors/                     # 拦截器
    ├── app_response_interceptor.dart # 响应处理 + 业务错误弹窗
    ├── network_error_interceptor.dart# 网络错误处理 + 自动弹窗
    ├── auth_interceptor.dart         # Token 注入
    ├── retry_interceptor.dart        # 失败重试
    └── error_interceptor.dart        # HTTP 错误处理
```

### 文件说明

| 文件                             | 职责                                                                |
| -------------------------------- | ------------------------------------------------------------------- |
| `app_error_code.dart`            | 统一错误码常量定义，避免魔法数字                                    |
| `app_http.dart`                  | 核心请求客户端，封装 GET/POST/PUT/DELETE，统一返回 `AppResponse<T>` |
| `app_response.dart`              | 响应数据模型，包含 `code`、`msg`、`data`，提供多种便捷判断方法      |
| `response_adapter.dart`          | 将不同后端格式统一转换为标准结构                                    |
| `app_response_interceptor.dart`  | 业务错误拦截器：数据适配 + 业务错误自动弹窗                         |
| `network_error_interceptor.dart` | 网络错误拦截器：统一处理超时、连接失败等网络异常                    |
| `auth_interceptor.dart`          | 自动注入 `Authorization: Bearer xxx`                                |
| `retry_interceptor.dart`         | 网络超时自动重试                                                    |
| `error_interceptor.dart`         | 处理 401/403 等 HTTP 状态码                                         |

---

## 架构分层

```
    ┌─────────────────────────────────────┐
    │        UI Layer (Page)              │  ← Loading 展示 / 用户交互
    └─────────────────────────────────────┘
                      ↑
    ┌─────────────────────────────────────┐
    │       ViewModel Layer               │  ← 业务逻辑 / 状态管理
    └─────────────────────────────────────┘
                      ↑
    ┌─────────────────────────────────────┐
    │        Service Layer                │  ← 数据获取 / 调用网络工具
    └─────────────────────────────────────┘
                      ↑
    ┌─────────────────────────────────────┐
    │      Interceptor Layer              │  ← 自动 Toast / 格式适配
    └─────────────────────────────────────┘
                      ↑
    ┌─────────────────────────────────────┐
    │     Network Layer (AppHttp)         │  ← 发送请求 / 接收响应
    └─────────────────────────────────────┘
```

### 各层职责

| 层级           | 职责                               | 不应该做                  |
| -------------- | ---------------------------------- | ------------------------- |
| **网络请求层** | 发送 HTTP 请求，返回 `AppResponse` | 不处理 UI，不抛异常       |
| **响应处理层** | 格式转换，自动弹出错误 Toast       | 不处理 Loading            |
| **业务层**     | 封装接口调用，数据转换             | 不处理 UI，不写 try-catch |
| **状态层**     | 管理页面状态，调用 Service         | 不直接调用网络层          |
| **UI 层**      | 展示 Loading/数据/错误，用户交互   | 不写业务逻辑              |

### Loading 和 Toast 放哪里？

| UI 类型        | 位置              | 原因                           |
| -------------- | ----------------- | ------------------------------ |
| **错误 Toast** | 拦截器自动处理    | 统一管理，无需重复代码         |
| **Loading**    | UI 层 / ViewModel | 与页面状态绑定，需根据业务展示 |

**设计原则：网络层是纯工具，不感知 UI。Loading 是页面状态，由 ViewModel 控制。**

---

## 快速开始

### 1. 初始化

在 `main.dart` 中调用一次：

```dart
import 'core/network/app_http.dart';
import 'core/network/interceptors/auth_interceptor.dart';
import 'core/network/interceptors/retry_interceptor.dart';

void main() {
  // 初始化网络层
  AppHttp.init(
    autoShowError: true, // 全局开启错误弹窗
    interceptors: [
      AuthInterceptor(getToken: () => ''), // Token 注入
      RetryInterceptor(dio: AppHttp().dio), // 自动重试
    ],
  );

  runApp(const MyApp());
}
```

### 2. 发起请求

在 Service 层直接调用，**无需 try-catch**：

```dart
class UserService {
  final _http = AppHttp();

  Future<AppResponse<User>> getUser(String id) async {
    return await _http.get<User>(
      '/users/$id',
      fromJson: (json) => User.fromJson(json),
    );
  }

  Future<AppResponse> createUser(Map<String, dynamic> data) async {
    return await _http.post('/users', data: data);
  }
}
```

### 3. 处理响应

在 ViewModel 层判断状态：

```dart
final res = await _service.getUser('123');

if (res.isSuccess) {
  // 成功 - 使用 res.data
  user.value = res.data;
} else {
  // 失败 - 错误已自动弹窗，这里可做额外处理
  if (res.isUnauthorized) {
    // 跳转登录页
    Get.offAllNamed('/login');
  } else if (res.isForbidden) {
    // 权限不足提示
  }
}
```

---

## 核心功能

### AppResponse 响应模型

所有请求返回此对象，不再抛出异常：

```dart
class AppResponse<T> {
  final int code;        // 状态码 (0/200 = 成功)
  final String msg;      // 消息
  final T? data;         // 业务数据
  final dynamic originalData; // 原始数据

  // 状态判断方法
  bool get isSuccess => code == AppErrorCode.success || code == AppErrorCode.successAlt;
  bool get isFailed => !isSuccess;
  bool get isUnauthorized => code == AppErrorCode.unauthorized;
  bool get isForbidden => code == AppErrorCode.forbidden;
  bool get isNetworkError => code == AppErrorCode.networkError;
  bool get isParseError => code == AppErrorCode.parseError;
}
```

### fromJson 自动解析

传入解析函数，自动将 `data` 转为对象：

```dart
// 解析单个对象
final res = await _http.get<User>(
  '/user/1',
  fromJson: (json) => User.fromJson(json),
);
User? user = res.data;

// 解析列表
final res = await _http.get<List<User>>(
  '/users',
  fromJson: (json) => (json as List).map((e) => User.fromJson(e)).toList(),
);
List<User>? users = res.data;
```

### showError 错误控制

控制是否自动弹出错误提示：

```dart
// 跟随全局配置 (默认)
await _http.get('/api');

// 强制弹窗
await _http.get('/api', showError: true);

// 静默模式 - 失败不弹窗
await _http.get('/api', showError: false);
```

---

## 参数配置

### AppHttp.init() 参数

| 参数            | 类型                 | 默认值                   | 说明             |
| --------------- | -------------------- | ------------------------ | ---------------- |
| `adapter`       | `AppResponseAdapter` | `DefaultResponseAdapter` | 响应格式适配器   |
| `interceptors`  | `List<Interceptor>`  | `[]`                     | 自定义拦截器     |
| `autoShowError` | `bool`               | `true`                   | 全局错误弹窗开关 |

### 请求方法参数

| 参数              | 类型                   | 说明                     |
| ----------------- | ---------------------- | ------------------------ |
| `path`            | `String`               | 请求路径                 |
| `data`            | `dynamic`              | 请求体 (POST/PUT/DELETE) |
| `queryParameters` | `Map<String, dynamic>` | URL 查询参数             |
| `fromJson`        | `T Function(dynamic)`  | 数据解析函数             |
| `showError`       | `bool?`                | 单次请求的错误弹窗控制   |
| `options`         | `Options`              | Dio 原生配置             |
| `cancelToken`     | `CancelToken`          | 取消令牌                 |

---

## 自定义扩展

### 自定义响应适配器

如果后端返回格式不是 `{code, msg, data}`，需要创建适配器：

```dart
// 后端格式: { "status": 0, "message": "ok", "result": {...} }
class MyAdapter extends AppResponseAdapter {
  @override
  Map<String, dynamic> adapt(dynamic json) {
    return {
      'code': json['status'] == 0 ? 200 : json['status'],
      'msg': json['message'] ?? '',
      'data': json['result'],
    };
  }
}

// 使用
AppHttp.init(adapter: MyAdapter());
```

### 内置适配器

| 适配器                   | 支持格式                                            |
| ------------------------ | --------------------------------------------------- |
| `DefaultResponseAdapter` | `{ "code": 200, "msg": "ok", "data": {...} }`       |
| `WanAndroidAdapter`      | `{ "errorCode": 0, "errorMsg": "", "data": {...} }` |

### 自定义拦截器

继承 `Interceptor` 类：

```dart
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print('REQUEST: ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print('RESPONSE: ${response.statusCode}');
    handler.next(response);
  }
}

// 使用
AppHttp.init(interceptors: [LoggingInterceptor()]);
```

---

## 内置拦截器

### NetworkErrorInterceptor (核心)

统一处理所有网络异常并自动弹窗：

```dart
NetworkErrorInterceptor(
  autoShowError: true, // 是否自动弹窗
)
```

**说明**：此拦截器已在 `AppHttp.init()` 中自动添加，无需手动配置。处理超时、连接失败等所有 Dio 网络异常。

### AppResponseInterceptor (核心)

处理业务错误并自动弹窗：

```dart
AppResponseInterceptor(
  adapter: DefaultResponseAdapter(), // 响应适配器
  autoShowError: true,               // 是否自动弹窗
)
```

**说明**：此拦截器已在 `AppHttp.init()` 中自动添加，无需手动配置。处理业务层错误（如 code != 200）。

### AuthInterceptor

自动注入 Token：

```dart
AuthInterceptor(
  getToken: () => StorageUtil.getString('token') ?? '',
)
```

### RetryInterceptor

网络超时自动重试：

```dart
RetryInterceptor(
  dio: AppHttp().dio,
  maxRetries: 3,              // 最大重试次数
  retryDelay: Duration(seconds: 1), // 重试间隔
)
```

### ErrorInterceptor

处理 HTTP 错误：

```dart
ErrorInterceptor(
  onUnauthorized: (_) => Navigator.pushNamed(context, '/login'),
  onForbidden: (_) => showToast('无访问权限'),
)
```

---

## 错误码常量

使用 `AppErrorCode` 统一管理错误码，避免魔法数字：

```dart
class AppErrorCode {
  // 成功码
  static const int success = 200;
  static const int successAlt = 0;

  // HTTP 状态码
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int serverError = 500;

  // 自定义错误码
  static const int networkError = -1;  // 网络错误
  static const int parseError = -2;    // 数据解析失败
  static const int timeout = -3;       // 请求超时
  static const int canceled = -4;      // 请求取消
  static const int unknown = -99;      // 未知错误
}
```
