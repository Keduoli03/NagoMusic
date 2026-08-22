import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';

/// 全 App 统一顶栏。样式对齐 flutter_template_local 的 `RefinedAppBar`：
/// **标题 17/w600 左对齐、不给副标题、返回键用尖角 `‹`**。
///
/// 与模板的一处关键差异：模板的顶栏是不透明的 `surface` 底 + 一条 hairline；
/// 这里默认**透明**，因为 NagoMusic 的页面普遍用 `extendBodyBehindAppBar` 让
/// 自定义背景图 / 播放页流光透到顶栏后面去。需要实底顶栏的页面自己传
/// [backgroundColor]，需要分隔线的传 `showDivider: true`。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final bool? centerTitle;
  final bool showBackButton;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double elevation;
  final double? height;
  final PreferredSizeWidget? bottom;

  /// 底部 0.5px hairline。透明顶栏下默认不画（内容会从它下面滚过去）。
  final bool showDivider;

  const AppTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.centerTitle,
    this.showBackButton = true,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
    this.height,
    this.bottom,
    this.showDivider = false,
  });

  static const double _defaultHeight = 56;

  @override
  Size get preferredSize => Size.fromHeight(
    (height ?? _defaultHeight) +
        (bottom?.preferredSize.height ?? 0) +
        // hairline 必须算进来，否则子页面顶栏底部会 overflow 0.5px 触发黄条。
        (showDivider ? 0.5 : 0),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = foregroundColor ?? c.text;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );

    final PreferredSizeWidget? bottomBar;
    if (!showDivider) {
      bottomBar = bottom;
    } else {
      final line = Container(height: 0.5, color: c.line);
      final inner = bottom;
      bottomBar = PreferredSize(
        preferredSize: Size.fromHeight(
          0.5 + (inner?.preferredSize.height ?? 0),
        ),
        child: inner == null
            ? line
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [inner, line],
              ),
      );
    }

    return AppBar(
      title:
          titleWidget ??
          (title != null
              ? Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    letterSpacing: 0.1,
                    height: 1.15,
                  ),
                )
              : null),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle ?? false,
      titleSpacing: leading == null && !showBackButton ? 20 : null,
      automaticallyImplyLeading: showBackButton,
      backgroundColor: backgroundColor ?? Colors.transparent,
      foregroundColor: fg,
      elevation: elevation,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: height ?? _defaultHeight,
      bottom: bottomBar,
      systemOverlayStyle: overlayStyle,
    );
  }
}
