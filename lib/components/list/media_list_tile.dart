import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../common/app_list_tile.dart';

class MediaListTile extends StatelessWidget {
  final Widget? leading;
  final String title;

  /// Optional widget rendered inline right after the title (e.g. a quality tag).
  final Widget? titleBadge;
  final String? subtitle;

  /// 钉在副标题最前面的小部件（音质标记）。见 [AppListTile.subtitleLeading]。
  final Widget? subtitleLeading;
  final bool selected;
  final bool multiSelect;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  const MediaListTile({
    super.key,
    this.leading,
    required this.title,
    this.titleBadge,
    this.subtitle,
    this.subtitleLeading,
    required this.selected,
    required this.multiSelect,
    required this.isHighlighted,
    required this.onTap,
    this.onLongPress,
    this.padding,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = isHighlighted
        ? theme.colorScheme.primary
        : AppColors.of(context).muted;
    final titleColor = isHighlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final leadingWidget = multiSelect
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              const SizedBox(width: 12),
              leading ?? const SizedBox.shrink(),
            ],
          )
        : leading;

    return AppListTile(
      leading: leadingWidget,
      title: title,
      titleBadge: titleBadge,
      subtitle: subtitle,
      subtitleLeading: subtitleLeading,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
