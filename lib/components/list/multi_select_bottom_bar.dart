import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';

/// 多选态的底部操作条。
///
/// 原来是一块贴着屏幕底、通铺 `scaffoldBackgroundColor` 的白板 —— 页面开了背景图
/// 或流光时它就是一块突兀的白砖。现在改成和 mini player 同族的**悬浮卡片**：
/// 左右留边、方角、`line` 描边 + 一层柔阴影，跟页面是同一套语言。
class MultiSelectBottomBar extends StatelessWidget {
  final List<MultiSelectAction> actions;

  const MultiSelectBottomBar({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadii.panel),
            border: Border.all(color: c.line, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: actions,
          ),
        ),
      ),
    );
  }
}

class MultiSelectAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  const MultiSelectAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // 常规动作走中性深色而不是主题强调色 —— 三个按钮并排时全上强调色太吵，
    // 只有破坏性动作才需要用颜色把自己单独标出来。
    final color = onTap == null
        ? c.muted.withValues(alpha: 0.5)
        : (isDestructive ? c.danger : c.text);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  isDestructive ? Haptics.heavy() : Haptics.tap();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
