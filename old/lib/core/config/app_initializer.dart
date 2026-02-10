import '../../services/display_mode_service.dart';
import '../network/app_http.dart';
import '../network/interceptors/index.dart';
import '../network/response_adapter.dart';
import 'app_config.dart';
/// 应用初始化器
///
/// 统一管理应用启动前的所有初始化逻辑
///
/// 使用示例:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AppInitializer.init();
///   runApp(const App());
/// }
/// ```
class AppInitializer {
  AppInitializer._();

  /// 初始化应用
  static Future<void> init({
    String? apiBaseUrl,
    bool? enableLog,
    bool useMockData = false,
  }) async {
    // 1. 初始化应用配置
    await AppConfig.init(
      apiBaseUrl: apiBaseUrl,
      enableLog: enableLog,
      useMockData: useMockData,
    );

    
    // 2. 初始化网络层
    _initNetwork();
    
    // 3. 初始化屏幕刷新率
    await DisplayModeService.init();

    // 4. 其他初始化 (埋点、推送等) - 可根据需要添加
  }

  
  /// 初始化网络层配置
  static void _initNetwork() {
    AppHttp.init(
      // 使用图虫 API 适配器 {result, message, feedList}
      adapter: TuChongAdapter(),

      // 自动显示错误弹窗 (默认 true)
      autoShowError: true,

      interceptors: [
        // Token 自动注入
        AuthInterceptor(
          getToken: () {
            // 从本地存储获取 token
            // return StorageUtil.getString('token') ?? '';
            return '';
          },
        ),
        // 请求重试
        RetryInterceptor(
          dio: AppHttp().dio,
          maxRetries: 3,
          retryDelay: const Duration(seconds: 1),
        ),
      ],
    );
  }
  }
