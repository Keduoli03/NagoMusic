import 'package:flutter/material.dart';

import '../../../app/theme/app_fonts.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool showBackButton;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;
  final double height;
  final PreferredSizeWidget? bottom;

  const AppTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.showBackButton = true,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
    this.height = 48,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppFonts.topBarTitleStyle(Theme.of(context).textTheme);
    return AppBar(
      title: titleWidget ?? (title != null ? Text(title!, style: titleStyle) : null),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      automaticallyImplyLeading: showBackButton,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: elevation,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: height,
      bottom: bottom,
    );
  }
}
