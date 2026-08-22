import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';

/// 弹窗外壳 —— 供 [AppDialog] 和其它自定义弹窗复用，保证视觉统一。
///
/// 移植自 flutter_template_local 的 `AppDialogShell`：
/// 宽度 = 屏宽 - 64，上限 340（避免平板上出现横长弹窗），圆角 22，无阴影。
class AppDialogShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppDialogShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 26, 24, 18),
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final dialogW = (w - 64).clamp(0.0, 340.0);
    return Dialog(
      backgroundColor: c.surface,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: ((w - dialogW) / 2).clamp(16.0, 60.0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogW),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 与 [AppDialog] 同款的胶囊按钮，对外暴露给自定义弹窗复用。
class AppDialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final Color? color;

  /// 点击触感强度：破坏性确认（删除/清空）给重震，其余给轻点。
  final bool destructive;

  const AppDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.filled,
    this.color,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cols = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? scheme.primary;
    return GestureDetector(
      onTap: () {
        destructive ? Haptics.heavy() : Haptics.tap();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? fill : cols.line,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: filled ? Colors.white : cols.text,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// 全局主题弹窗，替代原生 AlertDialog。
class AppDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String? contentText;
  final String cancelText;
  final String confirmText;
  final VoidCallback? onCancel;
  final VoidCallback onConfirm;
  final bool isDestructive;
  final bool showCancel;

  /// 标题上方的圆形图标。不传则不画。
  final IconData? icon;

  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.contentText,
    this.cancelText = '取消',
    this.confirmText = '确定',
    this.onCancel,
    required this.onConfirm,
    this.isDestructive = false,
    this.showCancel = true,
    this.icon,
  }) : assert(
         content != null || contentText != null,
         'Either content or contentText must be provided',
       );

  static Future<bool?> showConfirm(
    BuildContext context, {
    required String title,
    required String content,
    String cancelText = '取消',
    String confirmText = '确定',
    bool isDestructive = false,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: title,
        contentText: content,
        cancelText: cancelText,
        confirmText: confirmText,
        isDestructive: isDestructive,
        icon: icon,
        onConfirm: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final confirmColor = isDestructive ? c.danger : scheme.primary;
    // 纯文案弹窗居中排版；塞了自定义 content 的（表单/列表）保持左对齐，
    // 否则输入框、单选列表会被挤到中间。
    final centered = contentText != null;

    return AppDialogShell(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: confirmColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: confirmColor, size: 26),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.text,
                height: 1.35,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 10),
            if (contentText != null)
              Text(
                contentText!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.5),
              )
            else
              content!,
            const SizedBox(height: 24),
            Row(
              children: [
                if (showCancel) ...[
                  Expanded(
                    child: AppDialogButton(
                      label: cancelText,
                      filled: false,
                      onTap:
                          onCancel ?? () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppDialogButton(
                    label: confirmText,
                    filled: true,
                    color: confirmColor,
                    destructive: isDestructive,
                    onTap: () {
                      onConfirm();
                      Navigator.of(context).pop(true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
