import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class AppListTile extends StatelessWidget {
  final Widget? leading;
  final String? title;
  final Widget? titleWidget;

  /// Optional widget rendered inline right after [title] (e.g. a quality badge).
  /// Ignored when [titleWidget] is supplied.
  final Widget? titleBadge;
  final String? subtitle;

  /// Optional widget pinned at the *start* of the subtitle line, before the
  /// text (e.g. a quality badge). It sits outside the flexible text, so a long
  /// subtitle ellipsises around it instead of pushing it away.
  final Widget? subtitleLeading;
  final Color? titleColor;
  final Color? subtitleColor;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dense;
  final Color? backgroundColor;

  const AppListTile({
    super.key,
    this.leading,
    this.title,
    this.titleWidget,
    this.titleBadge,
    this.subtitle,
    this.subtitleLeading,
    this.titleColor,
    this.subtitleColor,
    this.trailing,
    this.contentPadding,
    this.onTap,
    this.onLongPress,
    this.dense = true,
    this.backgroundColor,
  });

  Widget? _buildTitle(Color color) {
    if (title == null) return null;
    final text = Text(
      title!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600),
    );
    if (titleBadge == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        const SizedBox(width: 6),
        titleBadge!,
      ],
    );
  }

  Widget? _buildSubtitle(Color color) {
    if (subtitle == null && subtitleLeading == null) return null;
    final text = subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12),
          );
    if (subtitleLeading == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        subtitleLeading!,
        if (text != null) Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultTitleColor = theme.colorScheme.onSurface;
    final defaultSubtitleColor = AppColors.of(context).muted;

    return Material(
      color: backgroundColor ?? Colors.transparent,
      child: ListTile(
        dense: dense,
        contentPadding: contentPadding,
        leading: leading,
        title: titleWidget ?? _buildTitle(titleColor ?? defaultTitleColor),
        subtitle: _buildSubtitle(subtitleColor ?? defaultSubtitleColor),
        trailing: trailing,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
