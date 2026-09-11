import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 屏幕底部那一整块东西 —— 迷你播放器 + 导航栏 —— 的共享尺寸和收起状态。
///
/// 参考 Apple Music：这两块不是各自独立的浮层，而是**一个整体**。展开时播放器
/// 是一条横贯的胶囊、底栏在它下面；往下滚页面时底栏收成「当前 Tab 一个圆圈」，
/// 播放器同时缩短、挪到那个圆圈右边，跟搜索圆圈并成一行。
///
/// 所以这里必须只有一份数字：布局是包里的 `GlassTabBar.minimizable` 算的，
/// 而列表底部要留多少白是我们自己算的，两边对不上就会出现「最后一首歌被挡住」
/// 或者「底下空一大块」。
abstract final class BottomChrome {
  /// 展开时胶囊本体的高度。图标 22 + 标签 11 + 间距，再留一点上下余量。
  static const double barHeight = 56;

  /// 收起后那个圆圈的直径。
  ///
  /// 迷你播放器收起时会被塞进这一行，包里给它的高度就是 [accessoryHeight]，
  /// 并且按 `(minimizedBarHeight - accessoryHeight) / 2` 居中 —— 两个数取一样，
  /// 圆圈和播放器胶囊才会严丝合缝地对齐，差一点就看得出一高一低。
  static const double minimizedBarHeight = 52;

  /// 迷你播放器的高度。展开、收起都是这个数（包里不会因为收起就压扁它）。
  static const double accessoryHeight = 52;

  /// 播放器和底栏之间的缝。
  static const double accessorySpacing = 6;

  /// 胶囊离屏幕底边的距离。
  static const double verticalPadding = 6;

  /// 这一整块**展开时**占的高度，不含系统手势区。
  ///
  /// 算法必须和包里 `GlassTabBar.preferredSize` 一致。收起时它会变矮，但页面留白
  /// 一律按展开算 —— 跟着收起缩，一往下滚内容就会往下窜一截。
  static double height({required bool withMiniPlayer}) {
    final pill = barHeight + verticalPadding * 2;
    if (!withMiniPlayer) return pill;
    return pill + accessorySpacing + accessoryHeight;
  }

  /// 全局唯一的收起控制器。
  ///
  /// 不能每个页面一个：四个主页面装在 IndexedStack 里同时存活，各自都有一份底栏。
  /// 各管各的话，在「歌曲」里滚到一半切到「我的」，那边的底栏还是展开的，切回来
  /// 又变回去 —— 底栏是全局的一块东西，状态也该是全局一份。
  ///
  /// `onScrollDown` 要显式开：默认的 `automatic` 实际解析成 `never`。
  static final GlassTabBarMinimizeController minimize =
      GlassTabBarMinimizeController(
        behavior: GlassBarMinimizeBehavior.onScrollDown,
      );
}
