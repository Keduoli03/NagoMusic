import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class AppBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final bool useSafeArea;

  const AppBottomBar({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bg = backgroundColor ?? colors.surface;
    final border = borderColor ?? colors.line;

    Widget body = Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 1)),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 20,
                offset: const Offset(0, -2),
              ),
            ],
      ),
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    );

    if (useSafeArea) {
      body = SafeArea(top: false, child: body);
    }
    return body;
  }
}
