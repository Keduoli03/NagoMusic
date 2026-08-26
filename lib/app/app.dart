import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/layout/tablet_layout_host.dart';
import 'router/app_page_route.dart';
import 'router/app_router.dart';
import 'state/settings_state.dart';
import 'theme/app_accents.dart';
import 'theme/app_page_transitions.dart';
import 'theme/app_surfaces.dart';
import 'theme/app_theme.dart';

class NagoMusicApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> baseNavigatorKey =
      GlobalKey<NavigatorState>();

  const NagoMusicApp({super.key});

  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CoverPageTransitionsBuilder(),
      TargetPlatform.iOS: CoverPageTransitionsBuilder(),
      TargetPlatform.macOS: CoverPageTransitionsBuilder(),
      TargetPlatform.windows: CoverPageTransitionsBuilder(),
      TargetPlatform.linux: CoverPageTransitionsBuilder(),
    },
  );

  /// 已构建好的主题，按 (种子色, 亮暗, 动态取色方案) 缓存。
  ///
  /// `ColorScheme.fromSeed` 要跑一遍 Material 3 的 HCT 色调板推导，是实打实的
  /// 计算量，而下面每次重建都要算**亮暗两套**。主题的输入其实极少变化，但它挂在
  /// `DynamicColorBuilder` + 三层 `ValueListenableBuilder` 底下，这四层里任何一个
  /// 抖一下（比如动态取色回调姗姗来迟）整条链就会把两套主题重算一遍。
  static final Map<(Color, Brightness, ColorScheme?), ThemeData> _themeCache =
      {};

  ThemeData _buildTheme({
    required Color seed,
    required Brightness brightness,
    required ColorScheme? dynamicScheme,
  }) {
    final key = (seed, brightness, dynamicScheme);
    final cached = _themeCache[key];
    if (cached != null) return cached;

    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      useMaterial3: true,
      pageTransitionsTheme: _pageTransitions,
    );
    final built = buildAppTheme(base, dynamicScheme ?? base.colorScheme);

    // 正常用法下键的组合就那么几种（预设强调色 × 亮暗），但用户拖主题色选择器时
    // 每个中间色都会落一条。设个上限，涨到头就整个丢掉重来。
    if (_themeCache.length >= 32) _themeCache.clear();
    _themeCache[key] = built;
    return built;
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: AppThemeSettings.themeMode,
          builder: (context, mode, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: AppThemeSettings.dynamicColorEnabled,
              builder: (context, dynamicEnabled, _) {
                return ValueListenableBuilder<Color?>(
                  valueListenable: AppThemeSettings.themeSeedColor,
                  builder: (context, seedColor, _) {
                    // 亮暗各自解析：命中预设时会拿到配对的那个颜色，
                    // 自选颜色时两边都用它本身。
                    final lightTheme = _buildTheme(
                      seed: AppAccents.resolve(seedColor, Brightness.light),
                      brightness: Brightness.light,
                      dynamicScheme: dynamicEnabled ? lightDynamic : null,
                    );
                    final darkTheme = _buildTheme(
                      seed: AppAccents.resolve(seedColor, Brightness.dark),
                      brightness: Brightness.dark,
                      dynamicScheme: dynamicEnabled ? darkDynamic : null,
                    );
                    final routes = AppRouter.routes;
                    Route<dynamic> onGenerateRoute(RouteSettings settings) {
                      final name = settings.name ?? AppRoutes.home;
                      final target = routes[name] ?? routes[AppRoutes.home]!;
                      return buildAppPageRoute<dynamic>(
                        target,
                        settings: settings,
                      );
                    }

                    return MaterialApp(
                      title: 'NagoMusic',
                      navigatorKey: rootNavigatorKey,
                      theme: lightTheme,
                      darkTheme: darkTheme,
                      themeMode: mode,
                      scrollBehavior: const AppScrollBehavior(),
                      home: TabletLayoutHost(
                        navigatorKey: baseNavigatorKey,
                        child: Navigator(
                          key: baseNavigatorKey,
                          initialRoute: AppRouter.initialRoute,
                          onGenerateRoute: onGenerateRoute,
                        ),
                      ),
                      onGenerateRoute: onGenerateRoute,
                      builder: (context, child) {
                        final theme = Theme.of(context);
                        final isDark = theme.brightness == Brightness.dark;
                        // 全局兜底的状态栏/导航栏样式。框架每帧只在图层树里找得到
                        // SystemUiOverlayStyle 注解时才下发样式，没有 AppBar 的
                        // 页面靠这一层才不会留着上一页的图标颜色。
                        //
                        // 系统导航栏**必须透明**：它不透明的话，屏幕最底下会有一条
                        // 满宽的直角色块，浮动胶囊底栏就像浮在一块白板上。透明之后
                        // App 自己画到屏幕最底，背景图/内容一路延伸到手势条底下。
                        // enforceSystemNavigationBarContrast 要一起关掉，否则
                        // Android 10+ 会自作主张在透明系统栏后面垫一层半透明灰。
                        final overlay = SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: isDark
                              ? Brightness.light
                              : Brightness.dark,
                          statusBarBrightness: isDark
                              ? Brightness.dark
                              : Brightness.light,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: isDark
                              ? Brightness.light
                              : Brightness.dark,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        );
                        return AnnotatedRegion<SystemUiOverlayStyle>(
                          value: overlay,
                          child: child ?? const SizedBox.shrink(),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
