import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import '../player/mini_player/mini_player_bar.dart';
import 'side_menu.dart';

class TabletLayoutHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const TabletLayoutHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<TabletLayoutHost> createState() => _TabletLayoutHostState();
}

class _TabletLayoutHostState extends State<TabletLayoutHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    if (AppLayoutSettings.tabletMode.value) {
      _controller.value = 1;
    }
    AppLayoutSettings.tabletMode.addListener(_handleModeChanged);
  }

  @override
  void dispose() {
    AppLayoutSettings.tabletMode.removeListener(_handleModeChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleModeChanged() {
    if (!mounted) return;
    final enabled = AppLayoutSettings.tabletMode.value;
    if (enabled) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final width = MediaQuery.sizeOf(context).width;
        final drawerWidth = (width * 0.32).clamp(200.0, 260.0);
        final pageOffset = drawerWidth * t;
        final scale = 1 - (0.02 * t);
        final contentWidth = (width - pageOffset).clamp(0.0, width);
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        final canPopRoot =
            !(widget.navigatorKey.currentState?.canPop() ?? false);
        return PopScope(
          canPop: canPopRoot,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (!canPopRoot) {
              widget.navigatorKey.currentState?.pop();
            }
          },
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRect(
                    child: Padding(
                      padding: EdgeInsets.only(left: pageOffset),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: contentWidth,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -drawerWidth + drawerWidth * t,
                  top: 0,
                  bottom: 0,
                  width: drawerWidth,
                  child: IgnorePointer(
                    ignoring: t == 0,
                    child: SideMenu(
                      onNavigate: _handleNavigate,
                      onPush: _handlePush,
                    ),
                  ),
                ),
                if (AppLayoutSettings.tabletMode.value)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset,
                    child: MiniPlayerBar(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }

  void _handleNavigate(String route) {
    widget.navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(route, (route) => false);
  }

  void _handlePush(String route) {
    widget.navigatorKey.currentState?.pushNamed(route);
  }
}
