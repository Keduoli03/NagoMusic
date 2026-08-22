import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/layout/tablet_layout_host.dart';
import 'router/app_page_route.dart';
import 'router/app_router.dart';
import 'state/settings_state.dart';
import 'theme/app_colors.dart';
import 'theme/app_styles.dart';
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

  ThemeData _buildTheme({
    required Color seed,
    required Brightness brightness,
    required ColorScheme? dynamicScheme,
  }) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      useMaterial3: true,
      pageTransitionsTheme: _pageTransitions,
    );
    return buildAppTheme(base, dynamicScheme ?? base.colorScheme);
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
                    final seed = seedColor ?? kBrand;
                    final lightTheme = _buildTheme(
                      seed: seed,
                      brightness: Brightness.light,
                      dynamicScheme: dynamicEnabled ? lightDynamic : null,
                    );
                    final darkTheme = _buildTheme(
                      seed: seed,
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
                        final navColor = theme.colorScheme.surface;
                        // 全局兜底的状态栏/导航栏样式。框架每帧只在图层树里找得到
                        // SystemUiOverlayStyle 注解时才下发样式，没有 AppBar 的
                        // 页面靠这一层才不会留着上一页的图标颜色。
                        final overlay = SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: isDark
                              ? Brightness.light
                              : Brightness.dark,
                          statusBarBrightness: isDark
                              ? Brightness.dark
                              : Brightness.light,
                          systemNavigationBarColor: navColor,
                          systemNavigationBarIconBrightness: isDark
                              ? Brightness.light
                              : Brightness.dark,
                          systemNavigationBarDividerColor: navColor,
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
