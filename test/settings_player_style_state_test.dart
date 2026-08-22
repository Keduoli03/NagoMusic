import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/state/settings_player_style_state.dart';

void main() {
  test('player style preset loads and saves selected preset', () async {
    SharedPreferences.setMockInitialValues({'player_style_preset': 'poster'});

    await PlayerStyleSettings.ensureLoaded();
    expect(PlayerStyleSettings.stylePreset.value, PlayerStylePreset.poster);

    await PlayerStyleSettings.setStylePreset(PlayerStylePreset.classic);
    expect(PlayerStyleSettings.stylePreset.value, PlayerStylePreset.classic);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player_style_preset'), 'classic');
  });
}
