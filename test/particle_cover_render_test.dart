import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/pages/player/widgets/particle_cover.dart';

void main() {
  testWidgets('playback starts from a complete crisp cover', (tester) async {
    final cover = File('assets/preview/style_preview_cover.jpg').absolute;
    expect(cover.existsSync(), isTrue);

    const side = 320;
    final boundaryKey = GlobalKey();
    late final ui.Image rendered;
    await tester.runAsync(
      () async => rendered = await renderParticleCoverSteadyForTesting(
        await cover.readAsBytes(),
        side: side,
        playbackProgress: 0,
      ),
    );
    addTearDown(rendered.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: side.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF24313F)),
                  RawImage(image: rendered, fit: BoxFit.fill),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/particle_cover_start.png'),
    );
  });

  testWidgets('steady cover keeps a crisp center and particles only at edges', (
    tester,
  ) async {
    final cover = File('assets/preview/style_preview_cover.jpg').absolute;
    expect(cover.existsSync(), isTrue);

    const side = 320;
    final boundaryKey = GlobalKey();
    late final ui.Image rendered;
    await tester.runAsync(
      () async => rendered = await renderParticleCoverSteadyForTesting(
        await cover.readAsBytes(),
        side: side,
        playbackProgress: 1,
      ),
    );
    addTearDown(rendered.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: side.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF24313F)),
                  RawImage(image: rendered, fit: BoxFit.fill),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/particle_cover_steady.png'),
    );
  });

  testWidgets('one-third playback shows partially dispersed particles', (
    tester,
  ) async {
    final cover = File('assets/preview/style_preview_cover.jpg').absolute;
    expect(cover.existsSync(), isTrue);
    const side = 320;
    final boundaryKey = GlobalKey();
    late final ui.Image rendered;
    await tester.runAsync(
      () async => rendered = await renderParticleCoverSteadyForTesting(
        await cover.readAsBytes(),
        side: side,
        playbackProgress: 0.32,
        motionPhase: 0.25,
      ),
    );
    addTearDown(rendered.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: side.toDouble(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF24313F)),
                  RawImage(image: rendered, fit: BoxFit.fill),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/particle_cover_mid.png'),
    );
  });
}
