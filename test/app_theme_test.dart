import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/theme/app_colors.dart';
import 'package:nagomusic/app/theme/app_theme.dart';

ThemeData _theme(Brightness brightness) {
  final source = ColorScheme.fromSeed(
    seedColor: kBrand,
    brightness: brightness,
  );
  return buildAppTheme(
    ThemeData(colorScheme: source, useMaterial3: true),
    source,
  );
}

void main() {
  test('AppColors token 被注册进 ThemeExtension', () {
    final light = _theme(Brightness.light);
    final dark = _theme(Brightness.dark);

    expect(light.extension<AppColors>(), AppColors.light);
    expect(dark.extension<AppColors>(), AppColors.dark);
  });

  test('浅色页面底是纯白，且 ColorScheme 跟着 AppColors 走', () {
    final theme = _theme(Brightness.light);

    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(theme.colorScheme.surface, AppColors.light.surface);
    expect(theme.colorScheme.onSurface, AppColors.light.text);
    expect(theme.colorScheme.onSurfaceVariant, AppColors.light.muted);
    expect(theme.colorScheme.outline, AppColors.light.line);
  });

  test('顶栏不会被 M3 的 surfaceTint / scrolledUnder 染灰', () {
    final theme = _theme(Brightness.light);

    expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
    expect(theme.appBarTheme.scrolledUnderElevation, 0);
  });

  test('裸 Switch 的开关两态轨道颜色不同', () {
    final theme = _theme(Brightness.light);
    final track = theme.switchTheme.trackColor!;
    final off = track.resolve(const <WidgetState>{})!;
    final on = track.resolve(const <WidgetState>{WidgetState.selected})!;

    expect(off, isNot(theme.colorScheme.surface));
    expect(on, theme.colorScheme.primary);
    expect(off, isNot(on));
  });
}
