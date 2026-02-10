import 'package:flutter/material.dart';
class StatusViewsTheme extends ThemeExtension<StatusViewsTheme> {
  final Widget Function(BuildContext ctx)? loadingBuilder;
  final Widget Function(BuildContext ctx, String? msg)? errorBuilder;
  final Widget Function(BuildContext ctx)? emptyBuilder;
  final Color? refreshIndicatorColor;
  final Widget Function(BuildContext ctx, bool hasMore)? loadMoreBuilder;
  const StatusViewsTheme({
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.refreshIndicatorColor,
    this.loadMoreBuilder,
  });
  @override
  StatusViewsTheme copyWith({
    Widget Function(BuildContext)? loadingBuilder,
    Widget Function(BuildContext, String?)? errorBuilder,
    Widget Function(BuildContext)? emptyBuilder,
    Color? refreshIndicatorColor,
    Widget Function(BuildContext, bool)? loadMoreBuilder,
  }) {
    return StatusViewsTheme(
      loadingBuilder: loadingBuilder ?? this.loadingBuilder,
      errorBuilder: errorBuilder ?? this.errorBuilder,
      emptyBuilder: emptyBuilder ?? this.emptyBuilder,
      refreshIndicatorColor:
          refreshIndicatorColor ?? this.refreshIndicatorColor,
      loadMoreBuilder: loadMoreBuilder ?? this.loadMoreBuilder,
    );
  }
  @override
  ThemeExtension<StatusViewsTheme> lerp(
    ThemeExtension<StatusViewsTheme>? other,
    double t,
  ) {
    return this;
  }
}

