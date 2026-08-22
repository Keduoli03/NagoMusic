import 'package:flutter/material.dart';

/// 默认品牌色。
///
/// 与 `flutter_template_local` 的 `kBrand` 同值。NagoMusic 与模板的区别在于：
/// 模板把 `kBrand` 当成写死的强调色，而这里它只是**默认种子色** —— 用户在
/// 「应用外观 → 主题色」里选过颜色、或打开了 Android 动态取色时，实际强调色
/// 来自 `Theme.of(context).colorScheme.primary`。
///
/// 所以：**页面里要用强调色时读 `colorScheme.primary`，不要直接用 `kBrand`**，
/// 否则用户换主题色时你这一处不会跟着变。
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
