import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cache/audio_cache_service.dart';

class AppThemeSettings {
  static const String _prefsThemeMode = 'setting_theme_mode';
  static const String _prefsDynamicColor = 'setting_dynamic_color_enabled';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier(ThemeMode.system);
  static final ValueNotifier<bool> dynamicColorEnabled =
      ValueNotifier(false);

  static bool _loaded = false;

  static ThemeMode _modeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = _modeFromString(prefs.getString(_prefsThemeMode));
    dynamicColorEnabled.value =
        prefs.getBool(_prefsDynamicColor) ?? false;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsThemeMode, _modeToString(mode));
    themeMode.value = mode;
  }

  static Future<void> setDynamicColorEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDynamicColor, enabled);
    dynamicColorEnabled.value = enabled;
  }
}

class WebDavPlaybackSettings {
  static const String _prefsPrefetchEnabled = 'webdav_prefetch_enabled';
  static const String _prefsSegmentedEnabled = 'webdav_segmented_enabled';
  static const String _prefsSegmentConcurrency = 'webdav_segment_concurrency';

  static final ValueNotifier<bool> prefetchEnabled = ValueNotifier(true);
  static final ValueNotifier<bool> segmentedEnabled = ValueNotifier(true);
  static final ValueNotifier<int> segmentConcurrency = ValueNotifier(4);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    prefetchEnabled.value = prefs.getBool(_prefsPrefetchEnabled) ?? true;
    segmentedEnabled.value = prefs.getBool(_prefsSegmentedEnabled) ?? true;
    segmentConcurrency.value =
        (prefs.getInt(_prefsSegmentConcurrency) ?? 4).clamp(1, 8);
  }

  static Future<void> setPrefetchEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsPrefetchEnabled, enabled);
    prefetchEnabled.value = enabled;
  }

  static Future<void> setSegmentedEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsSegmentedEnabled, enabled);
    segmentedEnabled.value = enabled;
  }

  static Future<void> setSegmentConcurrency(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final value = count.clamp(1, 8);
    await prefs.setInt(_prefsSegmentConcurrency, value);
    segmentConcurrency.value = value;
  }
}

class PlayerBottomActionSettings {
  static const String _prefsShowPlaybackMode = 'player_bottom_show_playback_mode';
  static const String _prefsShowSleepTimer = 'player_bottom_show_sleep_timer';
  static const String _prefsShowPlaylist = 'player_bottom_show_playlist';
  static const String _prefsShowMore = 'player_bottom_show_more';
  static const String _prefsActionOrder = 'player_bottom_action_order';

  static const List<String> _defaultActionOrder = [
    'playback_mode',
    'sleep_timer',
    'playlist',
    'more',
  ];

  static final ValueNotifier<bool> showPlaybackMode = ValueNotifier(true);
  static final ValueNotifier<bool> showSleepTimer = ValueNotifier(true);
  static final ValueNotifier<bool> showPlaylist = ValueNotifier(true);
  static final ValueNotifier<bool> showMore = ValueNotifier(true);
  static final ValueNotifier<List<String>> actionOrder =
      ValueNotifier(_defaultActionOrder);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    showPlaybackMode.value = prefs.getBool(_prefsShowPlaybackMode) ?? true;
    showSleepTimer.value = prefs.getBool(_prefsShowSleepTimer) ?? true;
    showPlaylist.value = prefs.getBool(_prefsShowPlaylist) ?? true;
    showMore.value = prefs.getBool(_prefsShowMore) ?? true;
    actionOrder.value = _normalizeOrder(prefs.getStringList(_prefsActionOrder));
  }

  static Future<void> setActionOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = _normalizeOrder(order);
    await prefs.setStringList(_prefsActionOrder, normalized);
    actionOrder.value = normalized;
  }

  static List<String> _normalizeOrder(List<String>? raw) {
    final seen = <String>{};
    final result = <String>[];
    if (raw != null) {
      for (final key in raw) {
        if (_defaultActionOrder.contains(key) && seen.add(key)) {
          result.add(key);
        }
      }
    }
    for (final key in _defaultActionOrder) {
      if (seen.add(key)) {
        result.add(key);
      }
    }
    return result;
  }

  static Future<void> setShowPlaybackMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowPlaybackMode, enabled);
    showPlaybackMode.value = enabled;
  }

  static Future<void> setShowSleepTimer(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowSleepTimer, enabled);
    showSleepTimer.value = enabled;
  }

  static Future<void> setShowPlaylist(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowPlaylist, enabled);
    showPlaylist.value = enabled;
  }

  static Future<void> setShowMore(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowMore, enabled);
    showMore.value = enabled;
  }
}

class AppCacheSettings {
  static const String _prefsAudioCacheLimitGb = 'audio_cache_limit_gb';

  static final ValueNotifier<int> audioCacheLimitGb = ValueNotifier(0);
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    audioCacheLimitGb.value =
        (prefs.getInt(_prefsAudioCacheLimitGb) ?? 0).clamp(0, 5);
    _applyCacheSettings();
  }

  static Future<void> setAudioCacheLimitGb(int gb) async {
    final prefs = await SharedPreferences.getInstance();
    final value = gb.clamp(0, 5);
    await prefs.setInt(_prefsAudioCacheLimitGb, value);
    audioCacheLimitGb.value = value;
    _applyCacheSettings();
  }

  static void _applyCacheSettings() {
    final gb = audioCacheLimitGb.value;
    final bytes = gb <= 0 ? 0 : gb * 1024 * 1024 * 1024;
    AudioCacheService.instance.setMaxCacheBytes(bytes);
  }
}

class MediaNotificationSettings {
  static const String _prefsShowLyrics = 'notification_show_lyrics';
  static const String _prefsShowCloseAction = 'notification_show_close_action';
  static const String _prefsLyricOnTop = 'notification_lyric_on_top';
  static const String _prefsShowFavoriteAction =
      'notification_show_favorite_action';

  static final ValueNotifier<bool> showLyrics = ValueNotifier(true);
  static final ValueNotifier<bool> showCloseAction = ValueNotifier(true);
  static final ValueNotifier<bool> lyricOnTop = ValueNotifier(false);
  static final ValueNotifier<bool> showFavoriteAction = ValueNotifier(true);

  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    showLyrics.value = prefs.getBool(_prefsShowLyrics) ?? true;
    showCloseAction.value = prefs.getBool(_prefsShowCloseAction) ?? true;
    lyricOnTop.value = prefs.getBool(_prefsLyricOnTop) ?? false;
    showFavoriteAction.value = prefs.getBool(_prefsShowFavoriteAction) ?? true;
  }

  static Future<void> setShowLyrics(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowLyrics, enabled);
    showLyrics.value = enabled;
  }

  static Future<void> setShowCloseAction(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowCloseAction, enabled);
    showCloseAction.value = enabled;
  }

  static Future<void> setLyricOnTop(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLyricOnTop, enabled);
    lyricOnTop.value = enabled;
  }

  static Future<void> setShowFavoriteAction(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsShowFavoriteAction, enabled);
    showFavoriteAction.value = enabled;
  }
}
