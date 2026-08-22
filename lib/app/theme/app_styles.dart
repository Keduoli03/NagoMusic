import 'package:flutter/material.dart';

import '../state/settings_background_state.dart';
import 'app_colors.dart';

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

extension AppThemeSurfaceX on ThemeData {
  bool get hasAmbientBackground {
    final backgroundPath = AppBackgroundSettings.backgroundImagePath.value;
    return AppBackgroundSettings.pageGlowEnabled.value ||
        (backgroundPath != null && backgroundPath.trim().isNotEmpty);
  }

  AppColors get appColors =>
      extension<AppColors>() ?? AppColors.forBrightness(brightness);

  /// 面板底色 = `AppColors.surface` × 「面板透明度」滑块。
  ///
  /// 页面底色现在是纯白，白卡叠白底本身看不出边界，所以面板的层次靠
  /// [appPanelBorderColor] 的描边和 [appPanelShadowColor] 的淡阴影撑起来；
  /// 透明度只在用户设了背景图 / 开了页面流光时才真正透出东西。
  Color get appPanelColor {
    final panelOpacity = AppBackgroundSettings.panelOpacity.value;
    if (panelOpacity <= 0) return Colors.transparent;
    return appColors.surface.withValues(alpha: panelOpacity);
  }

  Color get appPanelShadowColor {
    return brightness == Brightness.dark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.05);
  }

  Color get appPanelBorderColor => appColors.line;

  Color get appPanelElevatedColor => appColors.mediaBg;
}
