import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'router/app_router.dart';
import 'theme/app_styles.dart';

class AppThemeSettings {
  static const String _prefsThemeMode = 'setting_theme_mode';
  static const String _prefsDynamicColor = 'setting_dynamic_color_enabled';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);
  static final ValueNotifier<bool> dynamicColorEnabled =
      ValueNotifier(false);

  static bool _loaded = false;

  static ThemeMode _modeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = _modeFromString(prefs.getString(_prefsThemeMode));
    dynamicColorEnabled.value =
        prefs.getBool(_prefsDynamicColor) ?? false;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsThemeMode, _modeToString(mode));
    themeMode.value = mode;
  }

  static Future<void> setDynamicColorEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDynamicColor, enabled);
    dynamicColorEnabled.value = enabled;
  }
}

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
                );
              },
            );
          },
        );
      },
    );
  }
}
