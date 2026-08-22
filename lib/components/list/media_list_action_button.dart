import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';

/// 列表头部右上角的图标按钮（排序 / 多选）。
///
/// 这两个按钮以前是裸 `IconButton`，不指定颜色就继承主题的 `onSurfaceVariant`，
/// 渲染成灰色 —— 而同一行左边的「全选」和顶栏的图标都是深色，看着不是一套。
/// 这里统一取 [AppColors.text]。
///
/// [active] 为 true 时换成强调色淡底方块（和 `SoftIconButton` 同款），
/// 用来表示多选态已经开着。
class MediaListActionButton extends StatelessWidget {
  const MediaListActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(AppRadii.chip);

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: radius,
          ),
          child: Icon(icon, size: 21, color: active ? accent : c.text),
        ),
      ),
    );

    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}
