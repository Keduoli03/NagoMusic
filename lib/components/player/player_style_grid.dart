import 'package:flutter/material.dart';

import '../../app/state/settings_player_style_state.dart';
import '../../app/theme/tokens.dart';
import 'player_style_preview.dart';

/// 播放样式的选择网格：一排缩略卡片，点哪个就切到哪个。
///
/// 抽成独立组件是因为它现在有两个调用方——设置页里的完整列表，和播放页长按
/// 弹出的快捷面板（见 [showPlayerStylePickerSheet]）——原来只写在
/// `player_settings_page.dart` 里，第二个调用方接进来的话不该复制一份。
class PlayerStyleGrid extends StatelessWidget {
  const PlayerStyleGrid({
    super.key,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  final PlayerStylePreset selected;
  final ValueChanged<PlayerStylePreset> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - AppSpacing.md) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final preset in PlayerStylePreset.values)
                SizedBox(
                  width: itemWidth,
                  child: PlayerStyleCard(
                    preset: preset,
                    selected: preset == selected,
                    onTap: () => onSelected(preset),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 单张样式缩略卡片：预览图 + 选中角标 + 名称/说明。
class PlayerStyleCard extends StatelessWidget {
  const PlayerStyleCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PlayerStylePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.rCard,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: selected ? 0.22 : 0.12,
                      ),
                      blurRadius: selected ? 16 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: PlayerStylePreview(preset: preset, selected: selected),
              ),
              if (selected)
                Positioned(
                  right: AppSpacing.sm,
                  top: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      AppIcons.check,
                      size: 14,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            preset.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.meta
                .on(selected ? scheme.primary : scheme.onSurface)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            preset.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.micro.on(
              scheme.onSurfaceVariant.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}
