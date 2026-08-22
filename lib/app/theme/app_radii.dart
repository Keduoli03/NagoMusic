/// 全 App 的圆角刻度。
///
/// 视觉基准是首页「每日推荐」那排卡片 —— 偏方、克制的圆角，不是 Material 默认
/// 那种大圆角。所有卡片 / 瓦片 / 按钮都用 [card]，图标底之类的小元素用 [chip]。
///
/// **想整体调松或调紧只改这个文件**，不要在页面里写 `BorderRadius.circular(18)`
/// 之类的散值，否则页面之间又会各圆各的。
class AppRadii {
  const AppRadii._();

  /// 图标底、小徽标、缩略图
  static const double chip = 6;

  /// 音质标签之类的微型徽章 —— 高度只有十几 px，用 [chip] 会圆成胶囊
  static const double badge = 4;

  /// 卡片、瓦片、按钮 —— 首页「每日推荐」卡片就是这一档
  static const double card = 8;

  /// 分组卡片、大面板、输入框
  static const double panel = 14;

  /// 弹窗
  static const double dialog = 20;

  /// 底部面板
  static const double sheet = 24;

  /// 胶囊（Tab、标签、主 CTA）
  static const double pill = 999;
}
