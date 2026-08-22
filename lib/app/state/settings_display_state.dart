import 'pref_entry.dart';

/// Preferences that affect how song lists render, independent of the app theme.
class SongListDisplaySettings {
  /// Whether to show the Hi-Res / 无损 / HQ badge next to song titles.
  static final showQualityTag = PrefEntry.boolean(
    'song_list_show_quality_tag',
    defaultValue: true,
  );

  static final _group = PrefGroup([showQualityTag]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setShowQualityTag(bool enabled) =>
      showQualityTag.set(enabled);
}
