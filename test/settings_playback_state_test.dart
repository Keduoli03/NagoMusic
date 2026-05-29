import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/state/settings_playback_state.dart';

void main() {
  test('app playback volume loads, saves, and clamps values', () async {
    SharedPreferences.setMockInitialValues({'player_app_volume': 0.35});

    await AppPlaybackVolumeSettings.ensureLoaded();
    expect(AppPlaybackVolumeSettings.volume.value, 0.35);

    await AppPlaybackVolumeSettings.setVolume(1.4);
    expect(AppPlaybackVolumeSettings.volume.value, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('player_app_volume'), 1);
  });
}
