import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'package:nagomusic/app/state/song_state.dart';
import 'package:nagomusic/pages/player/widgets/player_background.dart';

void main() {
  testWidgets('brightness override keeps immersive player dark in light mode', (
    tester,
  ) async {
    PlayerBackgroundSettings.playbackThemeMode.value = ThemeMode.light;
    addTearDown(
      () => PlayerBackgroundSettings.playbackThemeMode.value = ThemeMode.system,
    );

    late Brightness brightness;
    late Color foreground;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: PlayerTheme(
          brightnessOverride: Brightness.dark,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              brightness = theme.brightness;
              foreground = theme.colorScheme.onSurface;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(brightness, Brightness.dark);
    expect(foreground.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('brightness override keeps cover-derived background dark', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await PlayerBackgroundSettings.ensureLoaded();
    PlayerBackgroundSettings.dynamicGradientEnabled.value = true;
    addTearDown(
      () => PlayerBackgroundSettings.dynamicGradientEnabled.value = false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: PlayerBackground(
          songSignal: signal<SongEntity?>(null),
          brightnessOverride: Brightness.dark,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    bool? isDark;
    for (final paint in tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    )) {
      final painter = paint.painter;
      if (painter != null &&
          painter.runtimeType.toString().contains('Aurora')) {
        isDark = (painter as dynamic).isDark as bool;
      }
    }
    expect(isDark, isTrue);
  });
}
