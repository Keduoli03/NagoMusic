import 'package:flutter/material.dart';

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
    // Incoming page: ease in from the right with a short fade.
    final inCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slideIn = inCurve.drive(
      Tween(begin: const Offset(0.16, 0), end: Offset.zero),
    );
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      reverseCurve: const Interval(0.45, 1.0, curve: Curves.easeIn),
    );

    Widget result = SlideTransition(
      position: slideIn,
      child: FadeTransition(opacity: fadeIn, child: child),
    );

    // Outgoing page (covered by a new route): subtle parallax to the left so
    // the stack feels layered instead of a flat cross-slide.
    if (secondaryAnimation.status != AnimationStatus.dismissed) {
      final outCurve = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      result = SlideTransition(
        position: outCurve.drive(
          Tween(begin: Offset.zero, end: const Offset(-0.08, 0)),
        ),
        child: result,
      );
    }
    return result;
  }
}
