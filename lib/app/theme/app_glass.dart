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
  /// 底色给淡、模糊调大：页面内容能透过来还被糊开，这才是磨砂。
  /// 底色太浓就成了一块不透光的白板，玻璃感全没；完全不给又会在浅色页面上
  /// 看不见（包的默认值就是全透明的白）。
  ///
  /// 菲涅尔和高光归零 —— 它们会在胶囊外沿描出一圈白边，在浅色页面上很脏。
  /// 层次交给底色和阴影，不靠那圈亮边。
  static LiquidGlassSettings panel(BuildContext context) {
    final c = AppColors.of(context);
    return LiquidGlassSettings(
      glassColor: c.surface.withValues(alpha: 0.30),
      blur: 18,
      shadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
      fresnelStrength: 0,
      lightIntensity: 0,
      glowIntensity: 0,
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
