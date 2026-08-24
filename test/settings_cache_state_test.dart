import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/state/settings_cache_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppCacheSettings.onLimitChanged = null;
  });

  // The limit must reach the bound callback even if a caller invokes the
  // setter before ensureLoaded() — otherwise eviction silently runs with a
  // stale cap.
  test(
    'setter pushes the limit to onLimitChanged without ensureLoaded',
    () async {
      var got = -1;
      AppCacheSettings.onLimitChanged = (bytes) => got = bytes;

      await AppCacheSettings.setAudioCacheLimitGb(3);

      expect(AppCacheSettings.audioCacheLimitGb.value, 3);
      expect(got, 3 * 1024 * 1024 * 1024);
    },
  );

  test('limit clamps to 0..5 and 0 means unlimited-off', () async {
    var got = -1;
    AppCacheSettings.onLimitChanged = (bytes) => got = bytes;

    await AppCacheSettings.setAudioCacheLimitGb(99);
    expect(AppCacheSettings.audioCacheLimitGb.value, 5);

    await AppCacheSettings.setAudioCacheLimitGb(0);
    expect(AppCacheSettings.audioCacheLimitGb.value, 0);
    expect(got, 0);
  });

  test('ensureLoaded applies the stored limit to the bound callback', () async {
    SharedPreferences.setMockInitialValues({'audio_cache_limit_gb': 2});
    var got = -1;
    AppCacheSettings.onLimitChanged = (bytes) => got = bytes;
    // PrefGroup caches its load future, so drop it or this depends on
    // whichever test happened to call ensureLoaded first.
    AppCacheSettings.debugResetLoaded();

    await AppCacheSettings.ensureLoaded();
    expect(AppCacheSettings.audioCacheLimitGb.value, 2);
    expect(got, 2 * 1024 * 1024 * 1024);
  });
}
