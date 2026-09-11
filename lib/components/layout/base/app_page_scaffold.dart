import 'package:flutter/material.dart';

import 'app_background.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/theme/app_glass.dart';
import '../../player/mini_player/mini_player_bar.dart';
import '../bottom_chrome.dart';
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
    // 玻璃模式下播放器和导航栏是**一块**东西（见 BottomChrome），高度由那边算，
    // 不能再把两个数各算一遍加起来 —— 加出来会比实际画的高一截，列表底下空一块。
    if (hasBottomNav &&
        AppLayoutSettings.bottomBarStyle.value ==
            AppBottomBarStyle.liquidGlass) {
      return bottomInset +
          BottomChrome.height(withMiniPlayer: showMiniPlayer) +
          minPadding;
    }
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
    this.showMiniPlayer = true,
  });

  @override
  State<AppPageScaffold> createState() => AppPageScaffoldState();
}

class AppPageScaffoldState extends State<AppPageScaffold> {
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

    Widget buildBody(bool glassChrome) {
      // 玻璃模式：播放器是底栏的 accessory，整块一起收起 —— 只有一层浮层。
      // 标准模式：还是老样子，播放器单独浮在导航栏上面。
      final bottomBar = hasBottomNav
          ? ModernNavigationBar(
              currentIndex: widget.bottomNavIndex!,
              onTap: widget.onBottomNavTap!,
              showMiniPlayer: widget.showMiniPlayer,
            )
          : null;
      final separateMiniPlayer = widget.showMiniPlayer && !glassChrome
          ? MiniPlayerBar(
              padding: hasBottomNav
                  ? const EdgeInsets.fromLTRB(
                      AppGlass.inset,
                      4,
                      AppGlass.inset,
                      0,
                    )
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            )
          : null;

      // viewPadding 而不是 padding：同上，键盘弹起时 padding.bottom 会塌成 0，
      // 迷你播放器会跟着往下掉一截。
      final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
      final miniPlayerBottom = hasBottomNav
          ? (AppPageScaffold.modernNavHeight + bottomInset)
          : bottomInset;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // 滚动方向喂给底栏的收起控制器。
          //
          // 挂在这里而不是各个页面里：页面各有各的 ScrollController（有的还嵌了
          // 好几层），逐个接一遍既繁琐又必然漏掉新页面。冒泡到这一层是所有可滚
          // 内容的必经之路，接一次就全覆盖了。
          //
          // 返回 false 让通知继续往上冒 —— 别的监听者（比如吸顶头部）还要用。
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              BottomChrome.minimize.handleNotification(notification);
              return false;
            },
            child: content,
          ),
          if (separateMiniPlayer != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: miniPlayerBottom,
              child: separateMiniPlayer,
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

    return AppBackground(
      child: ValueListenableBuilder<AppBottomBarStyle>(
        valueListenable: AppLayoutSettings.bottomBarStyle,
        builder: (context, barStyle, _) {
          final glassChrome =
              hasBottomNav && barStyle == AppBottomBarStyle.liquidGlass;
          return Scaffold(
            resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
            extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
            backgroundColor: Colors.transparent,
            appBar: widget.appBar,
            body: buildBody(glassChrome),
          );
        },
      ),
    );
  }
}
