import 'package:flutter/material.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class CoverPageTransitionsBuilder extends PageTransitionsBuilder {
  const CoverPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slideAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offsetTween = Tween(begin: const Offset(0.08, 0), end: Offset.zero);
    final content = SlideTransition(
      position: slideAnimation.drive(offsetTween),
      child: child,
    );
    if (secondaryAnimation.status != AnimationStatus.dismissed) {
      final fadeOut = CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0, 0.2),
      );
      return FadeTransition(
        opacity: ReverseAnimation(fadeOut),
        child: content,
      );
    }
    return content;
  }
}
