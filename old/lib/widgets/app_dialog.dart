import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String? contentText;
  final String cancelText;
  final String confirmText;
  final VoidCallback? onCancel;
  final VoidCallback onConfirm;
  final bool isDestructive;

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
  }) : assert(content != null || contentText != null, 'Either content or contentText must be provided');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface;
    
    return Dialog(
      backgroundColor: backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: double.infinity,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (contentText != null)
                  Text(
                    contentText!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(204),
                      height: 1.5,
                    ),
                  )
                else
                  content!,
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: isDark 
                                ? Colors.white.withAlpha(20)
                                : Colors.grey.withAlpha(26),
                            foregroundColor: isDark ? Colors.white70 : Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            elevation: 0,
                          ),
                          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
                          child: Text(
                            cancelText,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDestructive 
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).primaryColor,
                            foregroundColor: isDestructive 
                                ? Theme.of(context).colorScheme.onError
                                : Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            onConfirm();
                            // Usually we pop in the callback or here? 
                            // The original code popped in the callback action (Navigator.pop(ctx, true)).
                            // But this is a reusable widget, so we should probably pop here if the callback doesn't handle navigation.
                            // However, standard pattern is to pop with result.
                            // Let's assume onConfirm just does the action, or we pop true.
                            // To match showDialog<bool> pattern, we should pop true.
                            Navigator.of(context).pop(true);
                          },
                          child: Text(
                            confirmText,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
