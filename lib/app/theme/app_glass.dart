import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_colors.dart';

/// 液态玻璃的**唯一**一份参数。
///
/// 底栏（`ModernNavigationBar`）和迷你播放器（`MiniPlayerBar`）都从这里取 ——
/// 它俩上下贴着，材质稍微差一点就看得出来「不搭」。分两处各写各的必然漂移。
///
/// 每个值为什么是这个数，下面都写了理由。想调就改这里，两处一起变。
abstract final class AppGlass {
  /// 悬浮玻璃面板的圆角。底栏和迷你播放器共用同一档，读起来才像一套。
  static const double radius = 22;

  /// 悬浮面板离屏幕左右两边的距离。两者必须一致，否则边缘对不齐。
  static const double inset = 14;

  /// 玻璃本体。
  ///
  /// 与小野草底栏共用同一套稳定浅白玻璃参数。背景仍能透出大轮廓和颜色，
  /// 但浅色模式始终保留约 38% 的白色基底，深色封面不会吃掉导航内容。
  static LiquidGlassSettings panel(BuildContext context) {
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlassSettings(
      thickness: 18,
      blur: 3,
      chromaticAberration: 0,
      refractiveIndex: 1.16,
      saturation: 1.02,
      fresnelStrength: 0.72,
      ambientStrength: 0.08,
      ambientRim: 0.16,
      lightIntensity: 0.58,
      glowIntensity: 0.9,
      shadow: dark
          ? const <BoxShadow>[]
          : <BoxShadow>[
              BoxShadow(
                color: c.text.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: c.text.withValues(alpha: 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
      whitenGated: false,
      whitenStrength: dark ? 0.04 : 0.18,
      backerColor: dark
          ? c.bg.withValues(alpha: 0.09)
          : c.surface.withValues(alpha: 0.24),
    );
  }

  /// 底栏那块跟着手指走的选中指示器。
  ///
  /// 指示器是**两层接力**：静止时画一块实心色（`indicatorColor`），一按下/拖动
  /// 它就淡出，把显示权交给这层**画在文字之上**的玻璃透镜。所以这层的颜色必须
  /// 自己给，否则会出现「静止看得见、一拖就没」。
  ///
  /// 用中性色压暗而不是主题色：它压在文字上面，不透明会把字盖掉，而同样透明度
  /// 下中性色读起来更清楚。
  ///
  /// `thickness` 压到 8：玻璃的厚度决定边缘把光线弯折得多狠，而那圈白环就是
  /// 弯折的产物。压薄之后环淡下去，透镜感还在。
  static LiquidGlassSettings indicator(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSettings(
      bodyMode: GlassBodyMode.clear,
      glassColor: c.text.withValues(alpha: 0.10),
      thickness: 8,
      fresnelStrength: 0,
      lightIntensity: 0,
      glowIntensity: 0,
    );
  }
}
