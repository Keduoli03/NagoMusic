import 'package:flutter/material.dart';

class AppTheme {
  static const PageTransitionsTheme _pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
    },
  );

  /// 亮色主题（函数级注释）
  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: const Color(0xFF3B82F6),
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF3B82F6),
        secondary: Color(0xFF22C55E),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    );
  }

  /// 暗色主题（函数级注释）
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF60A5FA),
        secondary: Color(0xFF34D399),
        surface: Color(0xFF1E2228),
        onSurface: Color(0xFFE5E7EB),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Color(0xFF1E2228),
        foregroundColor: Color(0xFFE5E7EB),
      ),
      scaffoldBackgroundColor: const Color(0xFF15181D),
      cardColor: const Color(0xFF1E2228),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1E2228),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
