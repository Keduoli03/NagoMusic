import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

class SourceScanDialog extends StatelessWidget {
  final int processed;
  final int added;
  final int total;
  final bool isScanning;
  final VoidCallback onCancel;
  final VoidCallback onHide;

  const SourceScanDialog({
    super.key,
    required this.processed,
    required this.added,
    required this.total,
    this.isScanning = true,
    required this.onCancel,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFinished = !isScanning;
    final progress = total > 0 ? (processed / total).clamp(0.0, 1.0) : null;
    final panelColor = Color.alphaBlend(
      (isFinished ? scheme.primary : scheme.secondaryContainer).withValues(
        alpha: theme.brightness == Brightness.dark ? 0.18 : 0.12,
      ),
      scheme.surface,
    );
    final outlineColor = (isFinished ? scheme.primary : scheme.outlineVariant)
        .withValues(alpha: 0.26);
    final badgeBg = (isFinished ? scheme.primary : scheme.secondaryContainer)
        .withValues(alpha: theme.brightness == Brightness.dark ? 0.24 : 0.85);
    final badgeFg = isFinished ? scheme.primary : scheme.onSecondaryContainer;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: outlineColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isFinished ? '扫描完成' : '扫描中',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: badgeFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: isFinished ? '关闭' : '隐藏',
                      onPressed: onHide,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        AppIcons.close,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isFinished ? '音源扫描已完成' : '正在整理音源歌曲',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isFinished ? '本次已更新扫描结果，你可以继续浏览音源。' : '请稍等片刻，扫描会持续同步当前进度。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: isFinished ? 1 : progress,
                    backgroundColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.72,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isFinished ? scheme.primary : scheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: '已扫描',
                        value: '$processed',
                        accent: isFinished ? scheme.primary : scheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: '新增歌曲',
                        value: '$added',
                        accent: scheme.primary,
                      ),
                    ),
                  ],
                ),
                if (total > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '总计 $total 项',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!isFinished) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onCancel,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            side: BorderSide(
                              color: scheme.error.withValues(alpha: 0.28),
                            ),
                            foregroundColor: scheme.error,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('取消扫描'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: onHide,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          backgroundColor: isFinished
                              ? scheme.primary
                              : scheme.secondaryContainer,
                          foregroundColor: isFinished
                              ? scheme.onPrimary
                              : scheme.onSecondaryContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(isFinished ? '知道了' : '隐藏面板'),
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
