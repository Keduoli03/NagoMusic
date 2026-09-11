import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/router/app_router.dart';
import '../../app/state/settings_state.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_glass.dart';
import '../../app/theme/app_icons.dart';
import '../player/mini_player/mini_player_bar.dart';
import 'bottom_chrome.dart';

const _primaryNavigationRoutes = <String>[
  AppRoutes.home,
  AppRoutes.songs,
  AppRoutes.bili,
  AppRoutes.profile,
];

final ValueNotifier<int> primaryNavigationIndex = ValueNotifier<int>(0);
bool primaryNavigationShellActive = false;

void navigateToPrimaryDestination(BuildContext context, int index) {
  if (index < 0 || index >= _primaryNavigationRoutes.length) return;
  final scope = PrimaryNavigationScope.maybeOf(context);
  if (scope != null) {
    scope.onSelected(index);
    return;
  }
  if (primaryNavigationShellActive) {
    primaryNavigationIndex.value = index;
    Navigator.of(context).popUntil(
      (route) => route.settings.name == AppRoutes.home || route.isFirst,
    );
    return;
  }
  final routeName = _primaryNavigationRoutes[index];
  if (ModalRoute.of(context)?.settings.name == routeName) return;
  final pageBuilder = AppRouter.routes[routeName];
  if (pageBuilder == null) return;
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: routeName),
      pageBuilder: (context, animation, secondaryAnimation) =>
          pageBuilder(context),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
    (route) => false,
  );
}

class PrimaryNavigationScope extends InheritedWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const PrimaryNavigationScope({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required super.child,
  });

  static PrimaryNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PrimaryNavigationScope>();
  }

  @override
  bool updateShouldNotify(PrimaryNavigationScope oldWidget) {
    return currentIndex != oldWidget.currentIndex ||
        onSelected != oldWidget.onSelected;
  }
}

class ModernNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// 迷你播放器是否由这条底栏承载。
  ///
  /// 玻璃模式下播放器是底栏的 `bottomAccessory` —— 它要跟着底栏一起收起、
  /// 滑到 Tab 圆圈旁边去，所以必须长在底栏里面，不能是外面单独浮的一层。
  final bool showMiniPlayer;

  const ModernNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showMiniPlayer = true,
  });

  static const List<String> _labels = ['首页', '歌曲', 'B站', '我的'];
  static const List<IconData> _icons = [
    AppIcons.home,
    AppIcons.musicNotes,
    AppIcons.video,
    AppIcons.person,
  ];
  static const List<IconData> _activeIcons = [
    AppIconsFilled.home,
    AppIconsFilled.musicNotes,
    AppIconsFilled.video,
    AppIconsFilled.person,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return ValueListenableBuilder<AppBottomBarStyle>(
      valueListenable: AppLayoutSettings.bottomBarStyle,
      builder: (context, barStyle, _) {
        // Follow the same panel-opacity slider used by cards / setting panels so
        // the bottom bar visually belongs to the same surface family. Dragging
        // "面板透明度" to 100% turns the bar fully transparent — the page glow
        // (or background image) shows through instead of a hard white slab.
        return ValueListenableBuilder<double>(
          valueListenable: AppBackgroundSettings.panelOpacity,
          builder: (context, panelOpacity, _) {
            final tinted = Color.alphaBlend(
              scheme.primary.withValues(alpha: isDark ? 0.05 : 0.03),
              scheme.surface,
            );
            final barColor = tinted.withValues(alpha: panelOpacity);
            // The bar is the same white as the page in light mode, so it needs a
            // hairline of its own to stay readable against scrolling content.
            final edgeColor = AppColors.of(context).line;

            if (barStyle == AppBottomBarStyle.liquidGlass) {
              // 玻璃底栏整个交给 liquid_glass_widgets 的 GlassTabBar。
              //
              // 原来用的是 liquid_glass_easy：它只给「一块玻璃面板」，Tab、
              // 指示器、按压反馈全得自己拼（这个文件里原先那个挤压-拉伸的
              // _LiquidIndicator 就是自己写的），调不出满意的效果。
              //
              // 用 minimizable 而不是 bottom：往下滚页面时整条栏收成「当前 Tab
              // 一个圆圈」，迷你播放器同时缩短挪到它右边，和搜索圆圈并成一行 ——
              // Apple Music 那个形态。高度、收起状态见 BottomChrome。
              return SafeArea(
                top: false,
                child: _GlassBar(
                  currentIndex: currentIndex,
                  labels: _labels,
                  icons: _icons,
                  activeIcons: _activeIcons,
                  onTap: onTap,
                  showMiniPlayer: showMiniPlayer,
                ),
              );
            }

            return Material(
              color: barColor,
              elevation: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: edgeColor, width: 1)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: List.generate(_labels.length, (index) {
                        return Expanded(
                          child: _NavItem(
                            label: _labels[index],
                            selected: currentIndex == index,
                            onTap: () => onTap(index),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 液态玻璃底栏。视觉参数和 notebook 项目那套是同一份，调过的结论都在注释里。
class _GlassBar extends StatelessWidget {
  const _GlassBar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.activeIcons,
    required this.onTap,
    required this.showMiniPlayer,
  });

  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final ValueChanged<int> onTap;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = AppColors.of(context);

    // 选中项要盯着**全局**下标，不能只看 widget.currentIndex。
    //
    // 每个页面写死自己的下标（bottomNavIndex: 0/1/2/3），而 IndexedStack 让四个
    // 页面的底栏同时存在 —— 对任何一个实例来说 currentIndex 从头到尾没变过，
    // GlassTabBar 收不到 selectedIndex 的变化，指示器就只会「闪」过去而不是滑。
    // 盯全局的话四个实例同步动，切到哪个都是接着上一个的位置往下演。
    //
    // 非外壳模式（深链直接 push 路由）下全局值不更新，那时才用自己的下标。
    return ValueListenableBuilder<int>(
      valueListenable: primaryNavigationIndex,
      builder: (context, globalIndex, _) {
        final selected = primaryNavigationShellActive
            ? globalIndex
            : currentIndex;
        return GlassTabBar.minimizable(
          selectedIndex: selected.clamp(0, labels.length - 1),
          onTabSelected: (index) {
            // 切页时先把栏放回展开态：新页面是从头开始看的，没有理由还保持着
            // 上一页滚到一半时收起来的样子。
            BottomChrome.minimize.expand();
            if (index == selected) return;
            onTap(index);
          },
          // 收起状态由全局控制器管，滚动事件在 AppPageScaffold 里喂给它。
          minimizeController: BottomChrome.minimize,
          // 收起后点那个圆圈就是「把我的 Tab 还回来」。
          onMinimizedTabTap: BottomChrome.minimize.expand,
          trailingButton: GlassTabBarTrailingButton(
            icon: const Icon(AppIcons.search),
            label: '搜索',
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.search),
          ),
          bottomAccessory: showMiniPlayer
              ? MiniPlayerBar(asAccessory: true)
              : null,
          bottomAccessoryHeight: BottomChrome.accessoryHeight,
          bottomAccessorySpacing: BottomChrome.accessorySpacing,
          barHeight: BottomChrome.barHeight,
          minimizedBarHeight: BottomChrome.minimizedBarHeight,
          verticalPadding: BottomChrome.verticalPadding,
          horizontalPadding: AppGlass.inset,
          barBorderRadius: AppGlass.radius,
          tabPadding: const EdgeInsets.symmetric(horizontal: 2),
          iconSize: 22,
          iconLabelSpacing: 2,
          labelFontSize: 11,
          magnification: 1.05,
          indicatorExpansion: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          selectedIconColor: scheme.primary,
          unselectedIconColor: c.text.withValues(alpha: 0.62),
          selectedLabelColor: scheme.primary,
          unselectedLabelColor: c.text.withValues(alpha: 0.62),
          selectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
          // 玻璃材质从 AppGlass 取，和迷你播放器共用同一份 —— 它俩上下贴着，
          // 材质差一点就看得出来「不搭」。
          settings: AppGlass.panel(context),
          // 静止时画的实心色块。不能直接给半透明色 —— 玻璃会把背后糊掉，
          // 低透明度的色铺上去基本被吃干净，选中态就看不见了。
          indicatorColor: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.14),
            scheme.surface,
          ),
          indicatorSettings: AppGlass.indicator(context),
          indicatorPinchStrength: 0.4,
          // 按压光晕关掉：32px 模糊 + 8px 扩散糊开之后是一大片比指示器还大的
          // 白晕，在浅色栏上很脏。触感反馈已经有 Haptics，不差这一下视觉。
          interactionGlowColor: Colors.transparent,
          // 长按拖动时默认会让整条栏物理形变、文字跟着扭，拖到一半看不清停在
          // 哪一项。glowOnly 只在触点处亮一下、栏本身不动。
          interactionBehavior: GlassInteractionBehavior.glowOnly,
          tabs: [
            for (var i = 0; i < labels.length; i++)
              GlassTab(
                icon: Icon(icons[i]),
                activeIcon: Icon(activeIcons[i]),
                label: labels[i],
                semanticLabel: labels[i],
              ),
          ],
        );
      },
    );
  }
}

/// 标准底栏的一个 Tab。玻璃底栏的 Tab 由 GlassTabBar 自己画，不走这里。
class _NavItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = scheme.onSurface;
    final inactiveColor = scheme.onSurfaceVariant.withValues(alpha: 0.7);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        // Silence the platform click sound so tab switches don't punctuate the
        // music the user is playing.
        enableFeedback: false,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: selected ? activeColor : inactiveColor,
              fontSize: selected ? 16 : 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
            ),
            child: Text(label, maxLines: 1),
          ),
        ),
      ),
    );
  }
}
