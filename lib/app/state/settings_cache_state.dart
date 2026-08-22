import 'package:flutter/foundation.dart';

import '../services/cache/audio_cache_service.dart';
import 'pref_entry.dart';

class AppCacheSettings {
  static final audioCacheLimitGb = PrefEntry.integer(
    'audio_cache_limit_gb',
    sanitize: (v) => v.clamp(0, 5),
  );

  static final _group = PrefGroup([
    audioCacheLimitGb,
  ], onLoaded: _applyCacheSettings);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  @visibleForTesting
  static void debugResetLoaded() => _group.resetForTest();

  /// 写入后立即同步到 [AudioCacheService]。
  ///
  /// 这里显式调用而不是挂 listener：listener 只能在 [ensureLoaded] 里注册，
  /// 万一有调用方先调 setter 再 ensureLoaded，限额就不会下发到服务层。
  static Future<void> setAudioCacheLimitGb(int gb) async {
    await audioCacheLimitGb.set(gb);
    _applyCacheSettings();
  }

  static void _applyCacheSettings() {
    final gb = audioCacheLimitGb.value;
    final bytes = gb <= 0 ? 0 : gb * 1024 * 1024 * 1024;
    AudioCacheService.instance.setMaxCacheBytes(bytes);
  }
}

class SongDownloadSettings {
  static final customDirectoryPath = PrefEntry.nullableText(
    'song_download_custom_directory',
  );
  static final useCustomDirectory = PrefEntry.boolean(
    'song_download_use_custom_directory',
  );

  static final _group = PrefGroup([customDirectoryPath, useCustomDirectory]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setCustomDirectoryPath(String? path) =>
      customDirectoryPath.set(path);

  static Future<void> setUseCustomDirectory(bool enabled) =>
      useCustomDirectory.set(enabled);
}
