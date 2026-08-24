import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_radii.dart';

/// 淡底方角图标按钮 —— 替代 Material 的 `IconButton.filledTonal` / 裸 `IconButton`。
///
/// 原生那两个的问题：`filledTonal` 是个 40+ 的正圆，色块重、和页面里方角的卡片
/// 不是一个语言；裸 `IconButton` 又只剩一个孤零零的图标，看不出是可点的控件。
///
/// 这里是方角（[AppRadii.chip]）+ 强调色淡底，尺寸自定，和卡片同一套圆角语言。
///
/// ```dart
/// SoftIconButton(icon: AppIcons.play, onTap: play)          // 淡底
/// SoftIconButton(icon: AppIcons.play, onTap: play, filled: true) // 实心
/// ```
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 34,
    this.iconSize,
    this.color,
    this.tooltip,
    this.filled = false,
    this.radius,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// 外框边长（正方形）。
  final double size;

  /// 图标字号，默认取 [size] 的 0.55。
  final double? iconSize;

  /// 强调色，默认当前主题的 `colorScheme.primary`。
  final Color? color;

  final String? tooltip;

  /// true = 实心强调底 + 白图标（主操作）；false = 12% 淡底 + 强调色图标。
  final bool filled;

  /// 圆角，默认 [AppRadii.chip]。
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    final r = BorderRadius.circular(radius ?? AppRadii.chip);
    final bg = filled ? accent : accent.withValues(alpha: 0.12);
    final fg = filled ? Colors.white : accent;

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: r,
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap!();
              }
            : null,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, borderRadius: r),
          child: Icon(icon, size: iconSize ?? size * 0.55, color: fg),
        ),
      ),
    );

    if (!enabled) button = Opacity(opacity: 0.4, child: button);
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}
