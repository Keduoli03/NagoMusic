import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';

import 'package:nagomusic/app/state/pref_entry.dart';
import 'package:nagomusic/app/state/settings_layout_state.dart';
import 'package:nagomusic/app/state/settings_playback_state.dart';
import 'package:nagomusic/app/state/settings_theme_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PrefEntry', () {
    test('starts at the default value', () {
      expect(PrefEntry.boolean('k', defaultValue: true).value, isTrue);
      expect(PrefEntry.integer('k', defaultValue: 7).value, 7);
      expect(PrefEntry.text('k', defaultValue: 'x').value, 'x');
      expect(PrefEntry.nullableText('k').value, isNull);
    });

    test('load falls back to the default when the key is absent', () async {
      final prefs = await SharedPreferences.getInstance();
      final entry = PrefEntry.boolean('missing', defaultValue: true);
      entry.load(prefs);
      expect(entry.value, isTrue);
    });

    test('load reads a stored value', () async {
      SharedPreferences.setMockInitialValues({'flag': false});
      final prefs = await SharedPreferences.getInstance();
      final entry = PrefEntry.boolean('flag', defaultValue: true);
      entry.load(prefs);
      expect(entry.value, isFalse);
    });

    test('set persists and notifies', () async {
      final entry = PrefEntry.boolean('flag');
      var notified = 0;
      entry.addListener(() => notified++);

      await entry.set(true);

      expect(entry.value, isTrue);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('flag'), isTrue);
    });

    test('sanitize clamps on both load and set', () async {
      SharedPreferences.setMockInitialValues({'vol': 9.0});
      final prefs = await SharedPreferences.getInstance();
      final entry = PrefEntry.number(
        'vol',
        defaultValue: 1,
        sanitize: (v) => v.clamp(0.0, 1.0),
      );

      entry.load(prefs);
      expect(entry.value, 1.0, reason: 'stored 9.0 must clamp on load');

      await entry.set(-3);
      expect(entry.value, 0.0);
      expect(prefs.getDouble('vol'), 0.0, reason: 'clamped value is persisted');
    });

    test('nullableText removes the key for null and blank', () async {
      final entry = PrefEntry.nullableText('dir');
      await entry.set('/music');
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dir'), '/music');

      await entry.set(null);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('dir'), isFalse);
      expect(entry.value, isNull);

      await entry.set('/music');
      await entry.set('   ');
      prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('dir'), isFalse, reason: 'blank clears the key');
      // The in-memory value must agree with disk — a leftover '' here would
      // make the notifier report "a path is set" while none is stored.
      expect(entry.value, isNull, reason: 'blank normalizes to null');
    });

    test('nullableText load treats a stored blank as null', () async {
      SharedPreferences.setMockInitialValues({'dir': '  '});
      final entry = PrefEntry.nullableText('dir');
      entry.load(await SharedPreferences.getInstance());
      expect(entry.value, isNull);
    });
  });

  group('PrefGroup', () {
    test('ensureLoaded loads every entry once', () async {
      SharedPreferences.setMockInitialValues({'a': true, 'b': 5});
      final a = PrefEntry.boolean('a');
      final b = PrefEntry.integer('b');
      var loadedCalls = 0;
      final group = PrefGroup([a, b], onLoaded: () => loadedCalls++);

      await group.ensureLoaded();
      expect(a.value, isTrue);
      expect(b.value, 5);
      expect(loadedCalls, 1);

      await group.ensureLoaded();
      expect(loadedCalls, 1, reason: 'second call reuses the cached future');
    });

    test('resetForTest allows reloading', () async {
      SharedPreferences.setMockInitialValues({'a': true});
      final a = PrefEntry.boolean('a');
      final group = PrefGroup([a]);
      await group.ensureLoaded();
      expect(a.value, isTrue);

      SharedPreferences.setMockInitialValues({'a': false});
      group.resetForTest();
      await group.ensureLoaded();
      expect(a.value, isFalse);
    });
  });

  group('settings storage compatibility', () {
    // These lock the on-disk representation so a PrefEntry refactor can't
    // silently orphan a user's existing preferences.
    test('theme mode still reads and writes light/dark/system', () async {
      SharedPreferences.setMockInitialValues({'setting_theme_mode': 'dark'});
      AppThemeSettings.themeMode.load(await SharedPreferences.getInstance());
      expect(AppThemeSettings.themeMode.value, ThemeMode.dark);

      await AppThemeSettings.setThemeMode(ThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_theme_mode'), 'light');
    });

    test('unknown theme mode falls back to system', () async {
      SharedPreferences.setMockInitialValues({'setting_theme_mode': 'bogus'});
      AppThemeSettings.themeMode.load(await SharedPreferences.getInstance());
      expect(AppThemeSettings.themeMode.value, ThemeMode.system);
    });

    test('navigation style round-trips by enum name', () async {
      SharedPreferences.setMockInitialValues({
        'setting_navigation_style': 'bottomBar',
      });
      AppLayoutSettings.navigationStyle.load(
        await SharedPreferences.getInstance(),
      );
      expect(
        AppLayoutSettings.navigationStyle.value,
        AppNavigationStyle.bottomBar,
      );

      await AppLayoutSettings.setNavigationStyle(AppNavigationStyle.drawer);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('setting_navigation_style'), 'drawer');
    });

    test('theme seed color stores ARGB and clears on null', () async {
      await AppThemeSettings.setThemeSeedColor(const Color(0xFF3B82F6));
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('setting_theme_seed_color'), 0xFF3B82F6);

      await AppThemeSettings.setThemeSeedColor(null);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('setting_theme_seed_color'), isFalse);
      expect(AppThemeSettings.themeSeedColor.value, isNull);
    });

    test('player bottom action order drops unknown and backfills', () async {
      SharedPreferences.setMockInitialValues({
        'player_bottom_action_order': ['more', 'bogus', 'playlist'],
      });
      PlayerBottomActionSettings.actionOrder.load(
        await SharedPreferences.getInstance(),
      );
      expect(PlayerBottomActionSettings.actionOrder.value, [
        'more',
        'playlist',
        'playback_mode',
        'sleep_timer',
      ]);
    });
  });
}
