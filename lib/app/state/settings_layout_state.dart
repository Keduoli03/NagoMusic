import 'pref_entry.dart';

enum AppNavigationStyle { drawer, bottomBar }

/// 底栏外观。[liquidGlass] 由 `liquid_glass_easy` 渲染：Impeller 上折射实时背景，
/// Skia 上自动退化成磨砂（模糊 + 染色 + 描边），不需要我们自己探测后端。
enum AppBottomBarStyle { standard, liquidGlass }

class AppLayoutSettings {
  static final tabletMode = PrefEntry.boolean('setting_tablet_mode');
  static final navigationStyle = PrefEntry.enumeration<AppNavigationStyle>(
    'setting_navigation_style',
    values: AppNavigationStyle.values,
    defaultValue: AppNavigationStyle.drawer,
  );
  static final bottomBarStyle = PrefEntry.enumeration<AppBottomBarStyle>(
    'setting_bottom_bar_style',
    values: AppBottomBarStyle.values,
    defaultValue: AppBottomBarStyle.standard,
  );

  static final _group = PrefGroup([
    tabletMode,
    navigationStyle,
    bottomBarStyle,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setTabletMode(bool enabled) => tabletMode.set(enabled);

  static Future<void> setNavigationStyle(AppNavigationStyle style) =>
      navigationStyle.set(style);

  static Future<void> setBottomBarStyle(AppBottomBarStyle style) =>
      bottomBarStyle.set(style);
}
