import 'package:flutter/material.dart';

import 'app_background.dart';
import '../../player/mini_player/mini_player_bar.dart';
import '../modern_navigation_bar.dart';

class AppPageScaffold extends StatelessWidget {
  static const double modernNavHeight = 60.0;

  static double scrollableBottomPadding(
    BuildContext context, {
    bool hasBottomNav = false,
    bool showMiniPlayer = true,
    double minPadding = 24,
  }) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniPlayerPadding = showMiniPlayer ? MiniPlayerBar.estimatedHeight : 0.0;
    final bottomNavPadding = hasBottomNav ? modernNavHeight : 0.0;
    return bottomInset + miniPlayerPadding + bottomNavPadding + minPadding;
  }

  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool extendBodyBehindAppBar;
  final bool useSafeArea;
  final int? bottomNavIndex;
  final ValueChanged<int>? onBottomNavTap;
  final Widget? drawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final bool showMiniPlayer;

  const AppPageScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.extendBodyBehindAppBar = false,
    this.useSafeArea = true,
    this.bottomNavIndex,
    this.onBottomNavTap,
    this.drawer,
    this.scaffoldKey,
    this.showMiniPlayer = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = body;
    if (useSafeArea) {
      content = SafeArea(child: content);
    }

    final hasBottomNav = bottomNavIndex != null && onBottomNavTap != null;
    final bottomBar = hasBottomNav
        ? ModernNavigationBar(
            currentIndex: bottomNavIndex!,
            onTap: onBottomNavTap!,
          )
        : null;
    final miniPlayer = showMiniPlayer
        ? MiniPlayerBar(
            padding: hasBottomNav
                ? const EdgeInsets.fromLTRB(16, 4, 16, 0)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          )
        : null;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniPlayerBottom = hasBottomNav ? (modernNavHeight + bottomInset) : bottomInset;

    return Scaffold(
      key: scaffoldKey,
      extendBody: bottomBar != null,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      body: AppBackground(
        child: Stack(
          children: [
            content,
            if (miniPlayer != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: miniPlayerBottom,
                child: miniPlayer,
              ),
          ],
        ),
      ),
      drawer: drawer,
      bottomNavigationBar: bottomBar == null
          ? null
          : Material(
              type: MaterialType.transparency,
              child: bottomBar,
            ),
    );
  }
}
