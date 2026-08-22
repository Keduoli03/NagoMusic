import 'pref_entry.dart';

enum AppNavigationStyle { drawer, bottomBar }

class AppLayoutSettings {
  static final tabletMode = PrefEntry.boolean('setting_tablet_mode');
  static final navigationStyle = PrefEntry.enumeration<AppNavigationStyle>(
    'setting_navigation_style',
    values: AppNavigationStyle.values,
    defaultValue: AppNavigationStyle.drawer,
  );

  static final _group = PrefGroup([tabletMode, navigationStyle]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setTabletMode(bool enabled) => tabletMode.set(enabled);

  static Future<void> setNavigationStyle(AppNavigationStyle style) =>
      navigationStyle.set(style);
}
