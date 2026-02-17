import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'router/app_router.dart';
import 'state/settings_state.dart';
import 'theme/app_styles.dart';

class NagoMusicApp extends StatelessWidget {
  const NagoMusicApp({super.key});

  ThemeData _applyDynamic(ThemeData base, ColorScheme? scheme) {
    if (scheme == null) return base;
    return base.copyWith(
      colorScheme: scheme,
      primaryColor: scheme.primary,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
    );
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
                final lightBase = ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF3B82F6),
                    brightness: Brightness.light,
                  ),
                  useMaterial3: true,
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
                    },
                  ),
                );
                final darkBase = ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF3B82F6),
                    brightness: Brightness.dark,
                  ),
                  useMaterial3: true,
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
                      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
                    },
                  ),
                );
                final lightTheme = _applyDynamic(
                  lightBase,
                  dynamicEnabled ? lightDynamic : null,
                );
                final darkTheme = _applyDynamic(
                  darkBase,
                  dynamicEnabled ? darkDynamic : null,
                );
                return MaterialApp(
                  title: 'NagoMusic',
                  theme: lightTheme,
                  darkTheme: darkTheme,
                  themeMode: mode,
                  scrollBehavior: const AppScrollBehavior(),
                  initialRoute: AppRouter.initialRoute,
                  routes: AppRouter.routes,
                  builder: (context, child) {
                    final theme = Theme.of(context);
                    final isDark = theme.brightness == Brightness.dark;
                    final navColor = theme.colorScheme.surface;
                    final overlay = SystemUiOverlayStyle(
                      statusBarColor: Colors.transparent,
                      statusBarIconBrightness:
                          isDark ? Brightness.light : Brightness.dark,
                      statusBarBrightness:
                          isDark ? Brightness.dark : Brightness.light,
                      systemNavigationBarColor: navColor,
                      systemNavigationBarIconBrightness:
                          isDark ? Brightness.light : Brightness.dark,
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
  }
}
