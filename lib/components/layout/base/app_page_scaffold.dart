import 'package:flutter/material.dart';

import '../../../app/state/settings_state.dart';
import 'app_background.dart';
import '../../player/mini_player/mini_player_bar.dart';
import '../modern_navigation_bar.dart';

class AppPageScaffold extends StatefulWidget {
  static const double modernNavHeight = 52.0;

  static double scrollableBottomPadding(
    BuildContext context, {
    bool hasBottomNav = false,
    bool showMiniPlayer = true,
    double minPadding = 24,
  }) {
    // viewPadding 而不是 padding：调用方多半在 AppPageScaffold **之上**算这个值，
    // 享受不到正文那层 MediaQuery 修正。用 padding 的话，键盘一弹起列表底部留白
    // 就会少掉一条导航栏的高度，整个列表跟着往下窜一下。
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final miniPlayerPadding = showMiniPlayer
        ? MiniPlayerBar.estimatedHeight
        : 0.0;
    final bottomNavPadding = hasBottomNav ? modernNavHeight : 0.0;
    return bottomInset + miniPlayerPadding + bottomNavPadding + minPadding;
  }

  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool extendBodyBehindAppBar;
  final bool useSafeArea;
  final bool resizeToAvoidBottomInset;
  final int? bottomNavIndex;
  final ValueChanged<int>? onBottomNavTap;
  final Widget? drawer;
  final bool showMiniPlayer;

  const AppPageScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.extendBodyBehindAppBar = false,
    this.useSafeArea = true,
    this.resizeToAvoidBottomInset = false,
    this.bottomNavIndex,
    this.onBottomNavTap,
    this.drawer,
    this.showMiniPlayer = true,
  });

  @override
  State<AppPageScaffold> createState() => AppPageScaffoldState();
}

class AppPageScaffoldState extends State<AppPageScaffold>
    with SingleTickerProviderStateMixin {
  static const Duration _drawerDuration = Duration(milliseconds: 240);

  late final AnimationController _drawerController;
  bool _draggingDrawer = false;

  bool get _hasDrawer => widget.drawer != null;

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: _drawerDuration,
    );
  }

  void openDrawer() {
    if (!_hasDrawer) return;
    if (AppLayoutSettings.tabletMode.value) return;
    _drawerController.forward();
  }

  void closeDrawer() {
    if (!_hasDrawer) return;
    if (AppLayoutSettings.tabletMode.value) return;
    _drawerController.reverse();
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 页面正文一律对键盘「无感」：viewInsets 清零，padding.bottom 用 viewPadding
    // 复原。
    //
    // 只清 viewInsets 是不够的 —— Flutter 里 `padding = viewPadding - viewInsets`
    // 并且钳在 0。键盘顶起来的那一刻 `padding.bottom` 会从「导航栏高度」直接塌成
    // 0，于是 SafeArea 的底部留白、以及所有按 `MediaQuery.padding.bottom` 算出来的
    // 底部间距，全都缩掉一条导航栏 —— 这就是点搜索框时看到的那一下轻微拉伸。
    // 用 viewPadding 复原后，页面完全感知不到键盘，什么都不会动。
    //
    // 弹窗 / 底部面板 / Toast 不走这里（它们挂在 Navigator 的 Overlay 上，在这层
    // 之外），所以它们仍然能正常读到 viewInsets 把自己顶到键盘上方。
    final Widget content = Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        Widget inner = widget.body;
        // SafeArea 必须包在被修正的 MediaQuery 里面，否则它读到的还是塌掉的
        // padding。同时这个 Builder 位于 Scaffold 之下，`padding.top` 已经被
        // Scaffold 的 removeTopPadding 扣过，不会在顶栏下面多空一条状态栏。
        if (widget.useSafeArea) inner = SafeArea(child: inner);
        return MediaQuery(
          data: mq.copyWith(
            viewInsets: EdgeInsets.zero,
            padding: mq.padding.copyWith(bottom: mq.viewPadding.bottom),
          ),
          child: inner,
        );
      },
    );

    final hasBottomNav =
        widget.bottomNavIndex != null && widget.onBottomNavTap != null;
    final bottomBar = hasBottomNav
        ? ModernNavigationBar(
            currentIndex: widget.bottomNavIndex!,
            onTap: widget.onBottomNavTap!,
          )
        : null;
    final miniPlayer = widget.showMiniPlayer
        ? MiniPlayerBar(
            padding: hasBottomNav
                ? const EdgeInsets.fromLTRB(16, 4, 16, 0)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          )
        : null;

    // viewPadding 而不是 padding：同上，键盘弹起时 padding.bottom 会塌成 0，
    // 迷你播放器会跟着往下掉一截。
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final miniPlayerBottom = hasBottomNav
        ? (AppPageScaffold.modernNavHeight + bottomInset)
        : bottomInset;

    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.62).clamp(
      220.0,
      300.0,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: AppLayoutSettings.tabletMode,
      builder: (context, tabletMode, _) {
        Widget buildBody({required bool includeMiniPlayer}) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              if (miniPlayer != null && includeMiniPlayer)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: miniPlayerBottom,
                  child: miniPlayer,
                ),
              // Keep the navigation capsule in the page's paint stack instead
              // of mounting it in Scaffold.bottomNavigationBar. The Scaffold
              // slot is a full-width surface on some Android/theme combinations,
              // which leaves a white panel visible behind a floating capsule.
              // As an overlay, only the capsule paints; the AppBackground below
              // it continues all the way into the system navigation area.
              if (bottomBar != null)
                Positioned(left: 0, right: 0, bottom: 0, child: bottomBar),
            ],
          );
        }

        Widget page = Scaffold(
          resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
          extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
          backgroundColor: Colors.transparent,
          appBar: widget.appBar,
          body: buildBody(includeMiniPlayer: !tabletMode),
        );

        if (tabletMode || !_hasDrawer) {
          return AppBackground(child: page);
        }
        if (miniPlayer != null) {
          page = Scaffold(
            resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
            extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
            backgroundColor: Colors.transparent,
            appBar: widget.appBar,
            body: buildBody(includeMiniPlayer: false),
          );
        }
        final stack = AppBackground(
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _drawerController,
                builder: (context, child) {
                  final value = _drawerController.value;
                  return Transform.translate(
                    offset: Offset(-drawerWidth + drawerWidth * value, 0),
                    child: child,
                  );
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RepaintBoundary(
                    child: SizedBox(width: drawerWidth, child: widget.drawer),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _drawerController,
                builder: (context, child) {
                  final value = _drawerController.value;
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) {
                      _draggingDrawer = true;
                    },
                    onHorizontalDragUpdate: (details) {
                      if (!_draggingDrawer) return;
                      final delta = details.primaryDelta ?? 0;
                      if (delta == 0) return;
                      if (_drawerController.value == 0 && delta < 0) return;
                      if (_drawerController.value == 1 && delta > 0) return;
                      final next =
                          (_drawerController.value + delta / drawerWidth).clamp(
                            0.0,
                            1.0,
                          );
                      _drawerController.value = next;
                    },
                    onHorizontalDragEnd: (_) {
                      if (!_draggingDrawer) return;
                      _draggingDrawer = false;
                      if (_drawerController.value < 0.5) {
                        closeDrawer();
                      } else {
                        openDrawer();
                      }
                    },
                    child: Transform.translate(
                      offset: Offset(drawerWidth * value, 0),
                      child: child,
                    ),
                  );
                },
                child: RepaintBoundary(child: page),
              ),
              if (miniPlayer != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: miniPlayerBottom,
                  child: miniPlayer,
                ),
              AnimatedBuilder(
                animation: _drawerController,
                builder: (context, child) {
                  if (_drawerController.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: drawerWidth,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: closeDrawer,
                      onHorizontalDragUpdate: (details) {
                        final delta = details.primaryDelta ?? 0;
                        if (delta == 0) return;
                        final next =
                            (_drawerController.value + delta / drawerWidth)
                                .clamp(0.0, 1.0);
                        _drawerController.value = next;
                      },
                      onHorizontalDragEnd: (details) {
                        if (_drawerController.value < 0.5) {
                          closeDrawer();
                        } else {
                          openDrawer();
                        }
                      },
                      child: Container(color: Colors.transparent),
                    ),
                  );
                },
              ),
            ],
          ),
        );
        return stack;
      },
    );
  }
}
