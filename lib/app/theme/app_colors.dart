import 'package:flutter/material.dart';

/// 旧的默认品牌色，**已经不再是任何地方的默认值**。
///
/// 2026-08 换成博客那套配色后，默认强调色改由 `AppAccents.fallback` 提供
/// （亮色珊瑚红 / 暗色琥珀黄），这个常量只剩历史参考价值。
///
/// **页面里要用强调色一律读 `Theme.of(context).colorScheme.primary`**，
/// 不要直接用这个常量，也不要直接用 `AppAccents` 里的值 —— 否则用户换主题色、
/// 或者开了 Android 动态取色时，你这一处不会跟着变。
const kBrand = Color(0xFF20B889);

/// 收藏红。两个主题下固定，不进 [AppColors]。
const kLike = Color(0xFFFF6B6B);

/// 主题化的中性色 token，随浅色 / 深色切换。
///
/// 取自 `flutter_template_local/lib/theme/app_colors.dart`，两处偏差：
///
/// 1. `light.bg` 是**纯白**而不是模板的 `#F7F8F7`。模板靠「灰底 + 白卡」拉开
///    层次；这里页面和卡片同为纯白，层次改由 [line] 描边 + 一层极淡阴影承担
///    （见 `SurfaceCard` / `AppSettingSection`）。**改回灰底的话记得把那些
///    描边一起去掉**，否则会变成灰底 + 描边白卡的双重分隔，显脏。
/// 2. `light.line` 比模板深一档（`#EDEEF0` vs `#F0F1F2`），因为白卡画在白底上
///    时，`#F0F1F2` 的描边几乎看不见。
///
/// 这些 token 同时会被映射进 `ColorScheme`（见 `buildAppTheme`）：
/// `surface`←[surface]、`onSurface`←[text]、`onSurfaceVariant`←[muted]、
/// `outline`←[line]。所以老代码里的 `scheme.onSurface` 之类会自动拿到这套配色，
/// 不需要逐处改成 `AppColors.of(context).text`。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// 页面背景
  final Color bg;

  /// 卡片 / 顶栏 / 面板
  final Color surface;

  /// 主文字
  final Color text;

  /// 次要文字
  final Color muted;

  /// 分割线 / 描边
  final Color line;

  /// 图片占位底、输入框填充
  final Color mediaBg;

  /// 提醒色主体
  final Color warn;

  /// 提醒色浅底
  final Color warnBg;

  /// 危险色主体（删除等破坏性动作）
  final Color danger;

  /// 危险色浅底
  final Color dangerBg;

  /// 评分星色
  final Color star;

  const AppColors({
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.mediaBg,
    required this.warn,
    required this.warnBg,
    required this.danger,
    required this.dangerBg,
    required this.star,
  });

  static const light = AppColors(
    bg: Colors.white,
    surface: Colors.white,
    text: Color(0xFF1B1F23),
    muted: Color(0xFF8B929A),
    line: Color(0xFFEDEEF0),
    mediaBg: Color(0xFFF5F6F5),
    warn: Color(0xFFF08A3C),
    warnBg: Color(0xFFFFF4E5),
    danger: Color(0xFFE5484D),
    dangerBg: Color(0xFFFDECEC),
    star: Color(0xFFFFB020),
  );

  static const dark = AppColors(
    bg: Color(0xFF121212),
    surface: Color(0xFF1E1F22),
    text: Color(0xFFECEDEE),
    muted: Color(0xFF9AA0A6),
    line: Color(0xFF2C2E33),
    mediaBg: Color(0xFF26282C),
    warn: Color(0xFFF59E0B),
    warnBg: Color(0x33F59E0B),
    danger: Color(0xFFEF4444),
    dangerBg: Color(0x33EF4444),
    star: Color(0xFFFFC94A),
  );

  static AppColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  // ------------------------------------------------------------ 按强调色派生
  //
  // 取自作者博客（Astro / gyoza）的取色方案，见其
  // `scripts/generate-accent-css.mjs`。核心是**页面底色不是中性灰白，而是由强调色
  // 混出来的**：
  //
  //   亮色  bg = mix(#FAFAFA, accent, 5%)
  //   暗色  bg = mix(#000212, accent, 12%)
  //
  // 这样换主题色时整个页面的底色跟着走一点点，不会出现「彩色控件浮在死白纸上」
  // 的割裂感。5% / 12% 是刻意的小比例——再高就从"有温度的白"变成"有颜色的底"，
  // 文字对比度也会开始掉。
  //
  // 另外注意 [bg] 和 [surface] 从此**不再相等**（亮色下是暖白底 + 纯白卡）。
  // 这正是博客的做法：底色拉层次、卡片仍然纯白、再配 [line] 描边。原来那版
  // bg == surface == 纯白、全靠描边和阴影撑层次的方案到此为止。

  /// 亮色下的底色基准，会往强调色混 5%。
  static const _lightBgBase = Color(0xFFFAFAFA);

  /// 暗色下的底色基准，会往强调色混 12%。带一点点蓝，纯黑会显得发死。
  static const _darkBgBase = Color(0xFF000212);

  static Color _mix(Color base, Color accent, double weight) {
    return Color.from(
      alpha: 1,
      red: base.r + (accent.r - base.r) * weight,
      green: base.g + (accent.g - base.g) * weight,
      blue: base.b + (accent.b - base.b) * weight,
    );
  }

  /// 按当前强调色派生整套中性色。
  ///
  /// [accent] 传 `ColorScheme.primary`（用户自选主题色或 Android 动态取色）。
  static AppColors fromAccent(Color accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? dark : light;
    return base.copyWith(
      bg: _mix(
        isDark ? _darkBgBase : _lightBgBase,
        accent,
        isDark ? 0.12 : 0.05,
      ),
    );
  }

  /// 取当前主题的 AppColors；未注册时回退浅色，保证任何 context 都能用。
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? text,
    Color? muted,
    Color? line,
    Color? mediaBg,
    Color? warn,
    Color? warnBg,
    Color? danger,
    Color? dangerBg,
    Color? star,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      mediaBg: mediaBg ?? this.mediaBg,
      warn: warn ?? this.warn,
      warnBg: warnBg ?? this.warnBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      star: star ?? this.star,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      mediaBg: Color.lerp(mediaBg, other.mediaBg, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnBg: Color.lerp(warnBg, other.warnBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      star: Color.lerp(star, other.star, t)!,
    );
  }
}
