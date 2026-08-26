import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/pages/player/widgets/particle_cover.dart';

void main() {
  testWidgets('playing motion phase visibly moves edge particles', (
    tester,
  ) async {
    final cover = File('assets/preview/style_preview_cover.jpg').absolute;
    expect(cover.existsSync(), isTrue);

    late final ui.Image firstFrame;
    late final ui.Image laterFrame;
    await tester.runAsync(() async {
      final bytes = await cover.readAsBytes();
      firstFrame = await renderParticleCoverSteadyForTesting(
        bytes,
        playbackProgress: 0.72,
        motionPhase: 0,
      );
      laterFrame = await renderParticleCoverSteadyForTesting(
        bytes,
        playbackProgress: 0.72,
        motionPhase: 0.08,
      );
    });
    addTearDown(firstFrame.dispose);
    addTearDown(laterFrame.dispose);

    late final ByteData firstBytes;
    late final ByteData laterBytes;
    await tester.runAsync(() async {
      firstBytes = (await firstFrame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      laterBytes = (await laterFrame.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
    });
    final first = firstBytes.buffer.asUint8List();
    final later = laterBytes.buffer.asUint8List();
    var changedPixels = 0;
    for (var index = 0; index < first.length; index += 4) {
      final difference =
          (first[index] - later[index]).abs() +
          (first[index + 1] - later[index + 1]).abs() +
          (first[index + 2] - later[index + 2]).abs() +
          (first[index + 3] - later[index + 3]).abs();
      if (difference > 12) changedPixels++;
    }

    // 防止动画时钟仍在跑、画面却因为位移过小而肉眼等同静态。
    expect(changedPixels, greaterThan(700));
  });

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
