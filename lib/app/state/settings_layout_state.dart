import 'pref_entry.dart';

/// 底栏外观。[liquidGlass] 由 `liquid_glass_widgets` 的 GlassTabBar 渲染：
/// 磨砂底色 + 会液态形变的选中指示器，还支持长按拖动切 Tab。
enum AppBottomBarStyle { standard, liquidGlass }

class AppLayoutSettings {
  static final bottomBarStyle = PrefEntry.enumeration<AppBottomBarStyle>(
    'setting_bottom_bar_style',
    values: AppBottomBarStyle.values,
    defaultValue: AppBottomBarStyle.liquidGlass,
  );

  static final _group = PrefGroup([bottomBarStyle]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setBottomBarStyle(AppBottomBarStyle style) =>
      bottomBarStyle.set(style);
}
