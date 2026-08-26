import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/state/settings_player_style_state.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:nagomusic/components/player/player_style_preview.dart';
import 'package:nagomusic/pages/player/widgets/particle_cover.dart';

void main() {
  testWidgets('immersive style preview mirrors the live player structure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: PlayerStylePreview(preset: PlayerStylePreset.immersive),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final particleCover = find.byType(ParticleCover);
    expect(particleCover, findsOneWidget);
    expect(Theme.of(tester.element(particleCover)).brightness, Brightness.dark);
    expect(find.text('逆光'), findsOneWidget);
    expect(find.text('孙燕姿'), findsOneWidget);
    expect(find.text('1:28'), findsOneWidget);
    expect(find.text('4:29'), findsOneWidget);
    expect(find.text('12/80'), findsOneWidget);
    expect(find.byIcon(AppIconsFilled.pause), findsOneWidget);
    expect(find.text('HI-RES'), findsNothing);

    // 卸载预览，确保粒子动画控制器随组件一起正确释放。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
