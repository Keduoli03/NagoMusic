import 'package:flutter/material.dart';

import '../common/app_list_tile.dart';

class MediaListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
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
    this.subtitle,
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
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = isHighlighted
        ? theme.colorScheme.primary
        : (isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100));
    final titleColor =
        isHighlighted ? theme.colorScheme.primary : theme.colorScheme.onSurface;

    final leadingWidget = multiSelect
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? theme.colorScheme.primary : theme.disabledColor,
              ),
              const SizedBox(width: 12),
              leading ?? const SizedBox.shrink(),
            ],
          )
        : leading;

    return AppListTile(
      leading: leadingWidget,
      title: title,
      subtitle: subtitle,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
