import 'pref_entry.dart';

class MediaNotificationSettings {
  static final showLyrics = PrefEntry.boolean(
    'notification_show_lyrics',
    defaultValue: true,
  );
  static final showCloseAction = PrefEntry.boolean(
    'notification_show_close_action',
    defaultValue: true,
  );
  static final lyricOnTop = PrefEntry.boolean('notification_lyric_on_top');
  static final showFavoriteAction = PrefEntry.boolean(
    'notification_show_favorite_action',
    defaultValue: true,
  );

  static final _group = PrefGroup([
    showLyrics,
    showCloseAction,
    lyricOnTop,
    showFavoriteAction,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setShowLyrics(bool enabled) => showLyrics.set(enabled);

  static Future<void> setShowCloseAction(bool enabled) =>
      showCloseAction.set(enabled);

  static Future<void> setLyricOnTop(bool enabled) => lyricOnTop.set(enabled);

  static Future<void> setShowFavoriteAction(bool enabled) =>
      showFavoriteAction.set(enabled);
}
