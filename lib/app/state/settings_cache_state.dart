import 'package:flutter/foundation.dart';

import 'pref_entry.dart';

class AppCacheSettings {
  static final audioCacheLimitGb = PrefEntry.integer(
    'audio_cache_limit_gb',
    sanitize: (v) => v.clamp(0, 5),
  );

  static final _group = PrefGroup([
    audioCacheLimitGb,
  ], onLoaded: _applyCacheSettings);

  /// 由 `main.dart` 在 `WidgetsFlutterBinding.ensureInitialized()` 之后、
  /// 其他任何初始化之前绑定为 `AudioCacheService.instance.setMaxCacheBytes`。
  ///
  /// 这个状态类不允许反过来 import `lib/app/services/`（那是这个代码库里
  /// 唯一一处 state→service 依赖，已经通过这层回调反转掉了），所以限额的
  /// 下发方式只能是「谁需要谁来注册回调」而不是直接调用服务单例。
  static void Function(int bytes)? onLimitChanged;

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  @visibleForTesting
  static void debugResetLoaded() => _group.resetForTest();

  /// 写入后立即同步到 [onLimitChanged]。
  ///
  /// 这里显式调用而不是挂 listener：listener 只能在 [ensureLoaded] 里注册，
  /// 万一有调用方先调 setter 再 ensureLoaded，限额就不会下发到服务层。
  static Future<void> setAudioCacheLimitGb(int gb) async {
    await audioCacheLimitGb.set(gb);
    _applyCacheSettings();
  }

  static void _applyCacheSettings() {
    assert(
      onLimitChanged != null,
      'AppCacheSettings.onLimitChanged 没有在 main.dart 里绑定：这不会崩溃，'
      '但会让缓存大小限制彻底失效——AudioCacheService 永远收不到限额，'
      '磁盘缓存会无限增长。',
    );
    final gb = audioCacheLimitGb.value;
    final bytes = gb <= 0 ? 0 : gb * 1024 * 1024 * 1024;
    onLimitChanged?.call(bytes);
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
