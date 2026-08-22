import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// 圆角卡片壳。移植自 flutter_template_local。
///
/// 两个方言：
/// - [SurfaceCard]（默认 flat）：`radius 16 + border(line)`
/// - [SurfaceCard.elevated]：带柔和阴影，用于需要浮起效果的卡片
///
/// 页面底色是纯白，所以 flat 版的描边**不是可选装饰而是唯一的层次来源** ——
/// 关掉 `showBorder` 的白卡在白页上会完全消失。
///
/// 需要跟随「面板透明度」滑块的面板请用 `GlassPanel`，它是这个组件外面包了一层
/// 透明度逻辑。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
    this.radius = 16,
    this.color,
    this.borderColor,
    this.borderWidth = 0.5,
    this.showBorder = true,
    this.margin,
    this.onTap,
    this.height,
  }) : elevated = false,
       boxShadow = null;

  /// 带柔和阴影的卡片（浮层感）
  const SurfaceCard.elevated({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
    this.radius = 17,
    this.color,
    this.margin,
    this.onTap,
    this.boxShadow,
    this.height,
  }) : elevated = true,
       showBorder = false,
       borderColor = null,
       borderWidth = 0.5;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// 卡片背景色。默认 [AppColors.surface]，随主题切换。
  final Color? color;

  /// 描边色。默认 [AppColors.line]。
  final Color? borderColor;
  final double borderWidth;

  /// 是否画描边。elevated 版默认 false。
  final bool showBorder;

  /// 是否浮起（带阴影）
  final bool elevated;

  /// 自定义阴影，elevated 时才生效；null → 默认柔阴影
  final List<BoxShadow>? boxShadow;

  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bg = color ?? c.surface;
    final radii = BorderRadius.circular(radius);
    final defaultShadow = elevated
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ]
        : null;

    return Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radii,
        border: showBorder
            ? Border.all(color: borderColor ?? c.line, width: borderWidth)
            : null,
        boxShadow: boxShadow ?? defaultShadow,
      ),
      // 用 Material + InkWell 才能有涟漪；无 onTap 时省掉这一层。
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radii,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
  }
}
