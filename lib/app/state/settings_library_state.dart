import 'pref_entry.dart';

class LibraryRefreshSettings {
  static final autoRefreshLocalOnLaunch = PrefEntry.boolean(
    'library_auto_refresh_local_on_launch',
  );
  static final autoRefreshCloudOnLaunch = PrefEntry.boolean(
    'library_auto_refresh_cloud_on_launch',
  );

  static final _group = PrefGroup([
    autoRefreshLocalOnLaunch,
    autoRefreshCloudOnLaunch,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setAutoRefreshLocalOnLaunch(bool enabled) =>
      autoRefreshLocalOnLaunch.set(enabled);

  static Future<void> setAutoRefreshCloudOnLaunch(bool enabled) =>
      autoRefreshCloudOnLaunch.set(enabled);
}
