import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import '../../app/theme/app_styles.dart';

/// 跟随「面板透明度」滑块的面板容器。
///
/// 相当于 `SurfaceCard` 外面包了一层透明度逻辑：底色取
/// `theme.appPanelColor`（= `AppColors.surface` × 面板透明度），描边取
/// `AppColors.line`，浅色下再加一层极淡阴影。
///
/// 不需要跟随透明度滑块的普通卡片请直接用 `SurfaceCard`。
///
/// 早先这里用 `BackdropFilter` 做真实模糊，但开销大、开关又让透明度滑块看起来
/// 像坏了，所以只保留了可调透明度。[blurSigma] 仅为兼容旧调用点保留，不生效。
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry borderRadius;
  final Color? color;
  final Color? borderColor;
  final Color? shadowColor;
  final List<BoxShadow>? boxShadow;
  // Kept for source compatibility — no longer honoured. Left as `double?` so
  // callers can keep passing their old `blurSigma:` args without a compile
  // error, and so a future replacement (e.g. a subtle inner highlight tied to
  // this value) could reuse the parameter.
  final double? blurSigma;
  final VoidCallback? onTap;
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.color,
    this.borderColor,
    this.shadowColor,
    this.boxShadow,
    this.blurSigma,
    this.onTap,
    this.height,
  });

  BorderRadius get _resolvedBorderRadius {
    final value = borderRadius;
    if (value is BorderRadius) return value;
    return BorderRadius.circular(20);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to panelOpacity so dragging the "面板透明度" slider updates
    // every panel instantly, without needing to leave and re-enter the page.
    return ValueListenableBuilder<double>(
      valueListenable: AppBackgroundSettings.panelOpacity,
      builder: (context, _, _) => _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.appPanelColor;
    final resolvedBorderColor = borderColor ?? theme.appPanelBorderColor;
    final resolvedShadowColor = shadowColor ?? theme.appPanelShadowColor;
    final isInvisible = resolvedColor.a <= 0;
    final resolvedShadow =
        boxShadow ??
        (isInvisible
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: resolvedShadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]);

    final panel = Container(
      height: height,
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: _resolvedBorderRadius,
        border: isInvisible ? null : Border.all(color: resolvedBorderColor),
        boxShadow: resolvedShadow,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    final material = Material(
      color: Colors.transparent,
      child: onTap == null
          ? panel
          : InkWell(
              borderRadius: _resolvedBorderRadius,
              onTap: onTap,
              child: panel,
            ),
    );

    return ClipRRect(borderRadius: _resolvedBorderRadius, child: material);
  }
}
