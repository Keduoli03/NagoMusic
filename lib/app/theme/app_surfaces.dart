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
