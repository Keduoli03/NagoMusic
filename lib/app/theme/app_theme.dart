import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_icons.dart';
import 'app_radii.dart';

/// 全 App 的 ThemeData 构建入口，取代原来的 `buildMiuixMaterialTheme`。
///
/// 亮/暗两套走同一个函数，中性色差异全部由 [AppColors.light] / [AppColors.dark]
/// 承载；强调色来自 [source]（用户自选主题色或 Android 动态取色），所以这里
/// **不直接用 `kBrand`**。
///
/// 除了注册 `AppColors` 扩展，还把这些 token 反向映射进 `ColorScheme`，让老代码
/// 里成百上千处 `scheme.onSurface` / `scheme.outline` 自动拿到新配色，不必逐处
/// 改写成 `AppColors.of(context).text`。
ThemeData buildAppTheme(ThemeData base, ColorScheme source) {
  // 底色由强调色派生（博客的取色方案），所以这里不能再用写死的 light / dark。
  final c = AppColors.fromAccent(source.primary, source.brightness);
  final isDark = source.brightness == Brightness.dark;

  final scheme = source.copyWith(
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.mediaBg,
    surfaceContainerHighest: c.mediaBg,
    outline: c.line,
    outlineVariant: c.line,
    error: c.danger,
  );

  // 顶栏 17/w600 左对齐，与模板的 RefinedAppBar 一致。
  final textTheme = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
  );

  final pillShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.pill),
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    cardColor: c.surface,
    dividerColor: c.line,
    splashFactory: InkRipple.splashFactory,
    textTheme: textTheme,
    extensions: [c],
    // M3 默认会给顶栏叠 seed 色调，并在内容滚到顶栏下方时抬升成 surfaceContainer
    // ——表现就是「本该纯白的顶栏发灰」。两项都关掉，顶栏永远等于 surface。
    // 见到顶栏发灰先查这里，别去改 AppColors.surface。
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: c.text),
    ),
    // 裸 AppBar 的默认返回键（Material 带横线的 arrow_back）统一换成尖角 '‹'，
    // 与模板的 RefinedAppBar 保持一致。
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) =>
          const Icon(AppIcons.chevronLeft, size: 28),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 12,
      iconColor: c.muted,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.text,
      ),
      subtitleTextStyle: TextStyle(fontSize: 12, height: 1.35, color: c.muted),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: c.line,
      thickness: 0.5,
      space: 0.5,
      indent: 16,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.mediaBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: c.muted, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: pillShape,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: pillShape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: pillShape,
        side: BorderSide(color: c.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 40),
        shape: pillShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: const CircleBorder()),
    ),
    // 裸 Switch 的兜底皮肤。设置项请用 AppSettingSwitchTile（内部是 AppSwitch），
    // 这里只是保证个别还没换掉的 Switch 不至于和新配色打架。
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return isDark ? const Color(0xFF2A2A2C) : const Color(0xFFE7E7EA);
        }
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return isDark ? const Color(0xFF3A3A3C) : const Color(0xFFDFE2E5);
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return isDark ? const Color(0xFF707074) : const Color(0xFFB8B8BD);
        }
        return Colors.white;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
      overlayColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: 0.10),
      ),
      splashRadius: 20,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.panel),
          ),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.line)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      indicatorShape: pillShape,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
    ),
  );
}
