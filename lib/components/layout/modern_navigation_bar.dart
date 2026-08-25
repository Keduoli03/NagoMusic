import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as lg;

import '../../app/router/app_router.dart';
import '../../app/state/settings_state.dart';
import '../../app/theme/app_colors.dart';

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
  if (primaryNavigationShellActive &&
      AppLayoutSettings.navigationStyle.value == AppNavigationStyle.bottomBar) {
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

class AppNavigationModeBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool useBottomNavigation) builder;

  const AppNavigationModeBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppNavigationStyle>(
      valueListenable: AppLayoutSettings.navigationStyle,
      builder: (context, style, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppLayoutSettings.tabletMode,
          builder: (context, tabletMode, _) {
            return builder(
              context,
              style == AppNavigationStyle.bottomBar && !tabletMode,
            );
          },
        );
      },
    );
  }
}

class ModernNavigationBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ModernNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<ModernNavigationBar> createState() => _ModernNavigationBarState();
}

class _ModernNavigationBarState extends State<ModernNavigationBar>
    with SingleTickerProviderStateMixin {
  static const List<String> _labels = ['首页', '歌曲', 'B站', '我的'];

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  /// 指示器这一趟的起点和终点（以 tab 下标为单位，可以是小数）。
  late double _from = widget.currentIndex.toDouble();
  late double _to = widget.currentIndex.toDouble();

  /// 上一次全局选中的 tab。
  int _prevGlobal = primaryNavigationIndex.value;

  @override
  void initState() {
    super.initState();
    primaryNavigationIndex.addListener(_onGlobalIndexChanged);
  }

  /// 动画必须由**全局选中项**驱动，不能靠 `widget.currentIndex`。
  ///
  /// 每个页面都写死自己的下标（`bottomNavIndex: 0/1/2/3`），而 IndexedStack 让四个
  /// 页面的底栏同时存在。切 tab 实际上是换了一个「已经处于终态」的底栏实例 ——
  /// 对任何一个实例来说 `currentIndex` 从头到尾没变过，`didUpdateWidget` 永远不会
  /// 触发，指示器就只能「闪」过去。
  ///
  /// 这里每个实例只关心「我这一页刚被选中」这一个事件，起点取全局的上一个下标，
  /// 也就是指示器在**上一个底栏**上的视觉位置，接力下来正好连续。
  void _onGlobalIndexChanged() {
    final next = primaryNavigationIndex.value;
    final prev = _prevGlobal;
    _prevGlobal = next;
    if (next != widget.currentIndex || prev == next) return;
    _from = prev.toDouble();
    _to = next.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 1;
      return;
    }
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    primaryNavigationIndex.removeListener(_onGlobalIndexChanged);
    _slide.dispose();
    super.dispose();
  }

  double get _indicatorPos {
    final t = Curves.easeOutCubic.transform(_slide.value);
    return _from + (_to - _from) * t;
  }

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

            Widget buildItems({required bool glass, required double height}) {
              final row = SizedBox(
                height: height,
                child: Row(
                  children: List.generate(_labels.length, (index) {
                    final selected = widget.currentIndex == index;
                    return Expanded(
                      child: _NavItem(
                        label: _labels[index],
                        selected: selected,
                        glass: glass,
                        onTap: () => widget.onTap(index),
                      ),
                    );
                  }),
                ),
              );
              if (!glass) return row;
              return SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _LiquidIndicator(
                        animation: _slide,
                        positionOf: () => _indicatorPos,
                        travel: (_to - _from).abs(),
                        itemCount: _labels.length,
                        color: scheme.primary,
                      ),
                    ),
                    row,
                  ],
                ),
              );
            }

            if (barStyle == AppBottomBarStyle.liquidGlass) {
              final glassRadius = BorderRadius.circular(24);
              final glassBase = Color.alphaBlend(
                scheme.primary.withValues(alpha: isDark ? 0.08 : 0.04),
                scheme.surface,
              );
              // 不是一层均匀白蒙版：顶部反光、中部透景、底部轻微主题色回光
              // 分开绘制，背景通过高模糊参与颜色，但不会把文字原样透出来。
              // 悬浮胶囊，不是贴边通铺的方条 —— 这是玻璃能不能被看见的关键。
              // 贴边方条的背后只有页面底色，没东西可折射；留出左右边距和大圆角之后，
              // 内容从胶囊两侧和四个角穿过去，折射才有内容可弯。
              //
              // 高度刻意凑成和标准底栏一样的 52（48 胶囊 + 4 间距），
              // 这样 AppPageScaffold.modernNavHeight 不用改，
              // mini player 的位置和列表底部留白都不会错位。
              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: glassRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.24 : 0.14,
                          ),
                          blurRadius: 28,
                          spreadRadius: -2,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.08 : 0.32,
                          ),
                          blurRadius: 7,
                          spreadRadius: -1,
                          offset: const Offset(-1, -2),
                        ),
                      ],
                    ),
                    // 玻璃本体交给 liquid_glass_easy。
                    //
                    // 自己写的那版（着色器还在仓库里）在真机上折不出效果：
                    // `ImageFilter.shader` 只肯采样**原始未过滤**的背景，compose 和
                    // 嵌套都绕不过去，所以模糊永远进不到折射里。这个包的做法是把
                    // 模糊和着色器两个 BackdropFilter 作为 Stack 里的**兄弟节点**
                    // 前后绘制 —— 下面那个先把模糊结果画进图层，上面那个才采样得到。
                    child: lg.LiquidGlassLens(
                      style: lg.LiquidGlassStyle(
                        shape: lg.LiquidGlassShape.continuousRoundedRectangle(
                          cornerRadius: 24,
                        ),
                        appearance: lg.LiquidGlassAppearance(
                          blur: const lg.LiquidGlassBlur(
                            sigmaX: 12,
                            sigmaY: 12,
                          ),
                          // 提饱和度抵消模糊的灰雾感。
                          saturation: 1.4,
                          // 材质层刻意压得很淡：折射才是主角，盖一层奶白就全糊了。
                          color: glassBase.withValues(
                            alpha: isDark ? 0.28 : 0.20,
                          ),
                        ),
                        refraction: const lg.LiquidGlassRefraction(
                          distortion: 0.5,
                          // 折射带宽度，和圆角同量级。
                          distortionWidth: 24,
                          magnification: 1.02,
                          chromaticAberration: 0.006,
                        ),
                      ),
                      child: buildItems(glass: true, height: 48),
                    ),
                  ),
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
                  child: buildItems(glass: false, height: 52),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 选中项底下那颗会流动的指示器 —— 玻璃底栏「液态」感的主要来源。
///
/// 单纯让指示器平移过去只是个滑块，看不出液体。这里做的是**挤压-拉伸**
/// （squash & stretch）：飞行途中横向拉长、纵向变扁，落位时回弹成圆胶囊。
/// 拉伸量在中途最大、两端归零，用 `sin(pi * t)` 得到；跨的 tab 越多拉得越夸张。
/// 纵向按 `1/sqrt(横向)` 收缩，让它看起来像体积守恒的一坨液体而不是被拉变形的图片。
class _LiquidIndicator extends StatelessWidget {
  const _LiquidIndicator({
    required this.animation,
    required this.positionOf,
    required this.travel,
    required this.itemCount,
    required this.color,
  });

  final Animation<double> animation;

  /// 当前位置（tab 下标，含小数）。用回调而不是传值，是因为它依赖控制器的实时值。
  final double Function() positionOf;

  /// 这一趟跨了几个 tab，决定拉伸的夸张程度。
  final double travel;

  final int itemCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedTint = Color.alphaBlend(
      color.withValues(alpha: isDark ? 0.30 : 0.22),
      scheme.surface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / itemCount;
        final maxHeight = constraints.maxHeight;
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final p = animation.value;
            final center = (positionOf() + 0.5) * slotWidth;

            // 跨得越远拉得越狠，最多按 3 个 tab 封顶。
            final amount = (travel / 3.0).clamp(0.0, 1.0);
            final stretch = 1 + 0.85 * amount * math.sin(math.pi * p);
            // 体积守恒：横向拉长多少，纵向就收窄多少。
            final squash = 1 / math.sqrt(stretch);

            final baseWidth = slotWidth * 0.66;
            final baseHeight = math.min(34.0, maxHeight - 8);
            final w = baseWidth * stretch;
            final h = baseHeight * squash;

            return Stack(
              children: [
                Positioned(
                  left: center - w / 2,
                  top: (maxHeight - h) / 2,
                  width: w,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          selectedTint.withValues(alpha: isDark ? 0.72 : 0.78),
                          selectedTint.withValues(alpha: isDark ? 0.62 : 0.68),
                          color.withValues(alpha: isDark ? 0.42 : 0.34),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(h / 2),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.20 : 0.52,
                        ),
                        width: 0.7,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.22 : 0.12,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 玻璃底栏下为 true：选中态改用主题色文字，和底下那颗液态指示器同色。
  /// 指示器负责「液态」的动感，文字只负责可读性，两者不要互相抢戏。
  final bool glass;

  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.glass = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = AppColors.of(context);
    final activeColor = glass ? scheme.primary : scheme.onSurface;
    // 玻璃底栏是透明的，背后是深浅不定的页面内容 —— 未选中项**不能**用
    // `onSurfaceVariant @ 0.7` 那种浅灰，背景亮一点它就整个消失
    // （表现为「后两个 tab 没有文字，点一下才出来」）。改用不透明的主文字色
    // 压到 0.62，在亮底上仍然读得出，暗底上又不会喧宾夺主。
    final inactiveColor = glass
        ? c.text.withValues(alpha: 0.62)
        : scheme.onSurfaceVariant.withValues(alpha: 0.7);

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
