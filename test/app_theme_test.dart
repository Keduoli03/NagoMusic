import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/theme/app_accents.dart';
import 'package:nagomusic/app/theme/app_colors.dart';
import 'package:nagomusic/app/theme/app_theme.dart';

ThemeData _theme(Brightness brightness, {Color? seed}) {
  final source = ColorScheme.fromSeed(
    seedColor: seed ?? AppAccents.fallback.forBrightness(brightness),
    brightness: brightness,
  );
  return buildAppTheme(
    ThemeData(colorScheme: source, useMaterial3: true),
    source,
  );
}

void main() {
  test('AppColors token 被注册进 ThemeExtension', () {
    for (final brightness in Brightness.values) {
      final registered = _theme(brightness).extension<AppColors>();
      expect(registered, isNotNull);
      // 底色由强调色派生，所以不再等于 AppColors.light / .dark 那两个常量；
      // 其余中性色仍然照搬常量。
      final base = AppColors.forBrightness(brightness);
      expect(registered!.surface, base.surface);
      expect(registered.text, base.text);
      expect(registered.muted, base.muted);
      expect(registered.line, base.line);
    }
  });

  test('ColorScheme 跟着 AppColors 走', () {
    final theme = _theme(Brightness.light);
    final c = theme.extension<AppColors>()!;

    expect(theme.scaffoldBackgroundColor, c.bg);
    expect(theme.colorScheme.surface, c.surface);
    expect(theme.colorScheme.onSurface, c.text);
    expect(theme.colorScheme.onSurfaceVariant, c.muted);
    expect(theme.colorScheme.outline, c.line);
  });

  test('页面底色不再是纯白，而是往强调色偏了一点', () {
    // 博客那套取色方案的核心：bg = mix(#FAFAFA, accent, 5%)。
    // 纯白底会让彩色控件像浮在死白纸上，也让液态玻璃彻底看不见。
    final theme = _theme(Brightness.light);
    final bg = theme.scaffoldBackgroundColor;

    expect(bg, isNot(Colors.white));
    // 只偏 5%，仍然必须是「很白的白」，不能变成有颜色的底。
    expect(bg.r, greaterThan(0.9));
    expect(bg.g, greaterThan(0.9));
    expect(bg.b, greaterThan(0.9));
    // 卡片仍然是纯白，靠它和 bg 的差拉开层次。
    expect(theme.colorScheme.surface, Colors.white);
  });

  test('换强调色时底色跟着变', () {
    Color bgFor(Color seed) =>
        _theme(Brightness.light, seed: seed).scaffoldBackgroundColor;

    final warm = bgFor(const Color(0xFFF55555));
    final cool = bgFor(const Color(0xFF0396FF));

    expect(warm, isNot(cool));
    expect(warm.r, greaterThan(warm.b), reason: '红色强调色该把底色带暖');
    expect(cool.b, greaterThan(cool.r), reason: '蓝色强调色该把底色带冷');
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

  group('AppAccents', () {
    test('预设有 17 档，且亮暗值互不相同', () {
      expect(AppAccents.presets, hasLength(17));
      for (final accent in AppAccents.presets) {
        expect(
          accent.light,
          isNot(accent.dark),
          reason: '每档都该是亮/暗一对不同的颜色，不是同一个值',
        );
      }
    });

    test('存的是亮色值，暗色模式下解析成配对色', () {
      final first = AppAccents.presets.first;

      expect(AppAccents.resolve(first.light, Brightness.light), first.light);
      expect(AppAccents.resolve(first.light, Brightness.dark), first.dark);
    });

    test('没选过时用 fallback', () {
      expect(
        AppAccents.resolve(null, Brightness.light),
        AppAccents.fallback.light,
      );
      expect(
        AppAccents.resolve(null, Brightness.dark),
        AppAccents.fallback.dark,
      );
    });

    test('取色器自选的颜色不命中预设，亮暗都用它本身', () {
      const custom = Color(0xFF123456);

      expect(AppAccents.byLight(custom), isNull);
      expect(AppAccents.resolve(custom, Brightness.light), custom);
      expect(AppAccents.resolve(custom, Brightness.dark), custom);
    });
  });
}
