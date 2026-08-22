import 'package:flutter/material.dart';

import 'pref_entry.dart';

class AppThemeSettings {
  // ThemeMode.name 恰好就是原本存储的 'light' / 'dark' / 'system'，
  // 因此改用 PrefEntry.enumeration 不会影响已有的存档值。
  static final themeMode = PrefEntry.enumeration<ThemeMode>(
    'setting_theme_mode',
    values: ThemeMode.values,
    defaultValue: ThemeMode.system,
  );
  static final dynamicColorEnabled = PrefEntry.boolean(
    'setting_dynamic_color_enabled',
  );
  static final themeSeedColor = PrefEntry.nullableColor(
    'setting_theme_seed_color',
  );

  static final _group = PrefGroup([
    themeMode,
    dynamicColorEnabled,
    themeSeedColor,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setThemeMode(ThemeMode mode) => themeMode.set(mode);

  static Future<void> setDynamicColorEnabled(bool enabled) =>
      dynamicColorEnabled.set(enabled);

  static Future<void> setThemeSeedColor(Color? color) =>
      themeSeedColor.set(color);
}
