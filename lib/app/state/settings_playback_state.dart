import 'pref_entry.dart';

class AppPlaybackVolumeSettings {
  static final volume = PrefEntry.number(
    'player_app_volume',
    defaultValue: 1,
    sanitize: (v) => v.clamp(0, 1).toDouble(),
  );

  static final _group = PrefGroup([volume]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setVolume(double value) => volume.set(value);
}

class WebDavPlaybackSettings {
  static final prefetchEnabled = PrefEntry.boolean(
    'webdav_prefetch_enabled',
    defaultValue: true,
  );
  static final segmentedEnabled = PrefEntry.boolean(
    'webdav_segmented_enabled',
    defaultValue: true,
  );
  static final segmentConcurrency = PrefEntry.integer(
    'webdav_segment_concurrency',
    defaultValue: 4,
    sanitize: (v) => v.clamp(1, 8),
  );

  static final _group = PrefGroup([
    prefetchEnabled,
    segmentedEnabled,
    segmentConcurrency,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setPrefetchEnabled(bool enabled) =>
      prefetchEnabled.set(enabled);

  static Future<void> setSegmentedEnabled(bool enabled) =>
      segmentedEnabled.set(enabled);

  static Future<void> setSegmentConcurrency(int count) =>
      segmentConcurrency.set(count);
}

class AppLaunchPlaybackSettings {
  static final autoPlayOnAppLaunch = PrefEntry.boolean(
    'player_auto_play_on_app_launch',
  );
  static bool hasHandledAutoPlayThisSession = false;

  static final _group = PrefGroup([autoPlayOnAppLaunch]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setAutoPlayOnAppLaunch(bool enabled) =>
      autoPlayOnAppLaunch.set(enabled);
}

/// Whether to automatically check for app updates on launch and prompt the user.
class AppLaunchUpdateSettings {
  static final autoCheckUpdateOnLaunch = PrefEntry.boolean(
    'app_auto_check_update_on_launch',
  );
  static bool hasCheckedUpdateThisSession = false;

  static final _group = PrefGroup([autoCheckUpdateOnLaunch]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setAutoCheckUpdateOnLaunch(bool enabled) =>
      autoCheckUpdateOnLaunch.set(enabled);
}

class PlayerBottomActionSettings {
  static const List<String> _defaultActionOrder = [
    'playback_mode',
    'sleep_timer',
    'playlist',
    'more',
  ];

  static final showPlaybackMode = PrefEntry.boolean(
    'player_bottom_show_playback_mode',
    defaultValue: true,
  );
  static final showSleepTimer = PrefEntry.boolean(
    'player_bottom_show_sleep_timer',
    defaultValue: true,
  );
  static final showPlaylist = PrefEntry.boolean(
    'player_bottom_show_playlist',
    defaultValue: true,
  );
  static final showMore = PrefEntry.boolean(
    'player_bottom_show_more',
    defaultValue: true,
  );

  /// 底部动作顺序：过滤掉未知项，并补齐缺失的默认项。
  static final actionOrder = PrefEntry.stringList(
    'player_bottom_action_order',
    defaultValue: _defaultActionOrder,
    sanitize: _normalizeOrder,
  );

  static final _group = PrefGroup([
    showPlaybackMode,
    showSleepTimer,
    showPlaylist,
    showMore,
    actionOrder,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setActionOrder(List<String> order) =>
      actionOrder.set(order);

  static List<String> _normalizeOrder(List<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final key in raw) {
      if (_defaultActionOrder.contains(key) && seen.add(key)) {
        result.add(key);
      }
    }
    for (final key in _defaultActionOrder) {
      if (seen.add(key)) {
        result.add(key);
      }
    }
    return result;
  }

  static Future<void> setShowPlaybackMode(bool enabled) =>
      showPlaybackMode.set(enabled);

  static Future<void> setShowSleepTimer(bool enabled) =>
      showSleepTimer.set(enabled);

  static Future<void> setShowPlaylist(bool enabled) =>
      showPlaylist.set(enabled);

  static Future<void> setShowMore(bool enabled) => showMore.set(enabled);
}

class MiniPlayerInfoSettings {
  static final showLyricsInSubtitle = PrefEntry.boolean(
    'mini_player_show_lyrics_in_subtitle',
  );

  static final _group = PrefGroup([showLyricsInSubtitle]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setShowLyricsInSubtitle(bool enabled) =>
      showLyricsInSubtitle.set(enabled);
}
