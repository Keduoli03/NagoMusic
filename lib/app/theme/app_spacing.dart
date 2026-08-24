import 'package:flutter/widgets.dart';

/// 全 App 的间距刻度。
///
/// 在这层出现之前，页面里到处手写 `SizedBox(height: 10)`、
/// `EdgeInsets.symmetric(horizontal: 14)` 之类的散值，同一语义
/// （页面边距 / 卡片内边距 / 元素间隙）在不同页面漂好几档。
///
/// **想整体调松或调紧只改这个文件**，不要在页面里写 `SizedBox(height: 18)`
/// 之类的散值，否则页面之间又会各留各的白。
abstract final class AppSpacing {
  /// 4 —— 图标与文字的间距、紧凑元素间隙。
  static const double xs = 4;

  /// 8 —— 同组元素之间。
  static const double sm = 8;

  /// 12 —— 卡片内边距（紧凑）、列表项内部行距。
  static const double md = 12;

  /// 16 —— 页面左右边距、卡片内边距（常规）、区块之间。
  static const double lg = 16;

  /// 24 —— 区块之间（需要明显呼吸）。
  static const double xl = 24;

  /// 32 —— 大分段、空态上下留白。
  static const double xxl = 32;

  /// 页面水平内边距。`Padding(padding: AppSpacing.page, child: ...)`
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);

  /// 卡片常规内边距。
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// 卡片紧凑内边距。
  static const EdgeInsets cardTight = EdgeInsets.all(md);

  // 常用竖向间隔，省掉到处写 SizedBox(height: ...)
  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
  static const SizedBox gapXl = SizedBox(height: xl);

  // 常用横向间隔
  static const SizedBox wGapXs = SizedBox(width: xs);
  static const SizedBox wGapSm = SizedBox(width: sm);
  static const SizedBox wGapMd = SizedBox(width: md);
}
