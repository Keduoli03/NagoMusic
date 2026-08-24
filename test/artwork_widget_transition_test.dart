import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/artwork_service.dart';

void main() {
  test(
    'loads an external cached cover as bytes for player original artwork',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('artwork_widget_');
      addTearDown(() => tempDir.delete(recursive: true));
      final cover = File('${tempDir.path}/cover.bin');
      await cover.writeAsBytes(const [3, 1, 4, 1, 5]);

      final bytes = await ArtworkService.instance.loadArtworkBytes(
        uri: 'bili://test',
        localCoverPath: cover.path,
        localAssetId: null,
        isLocal: false,
        preferOriginal: true,
      );

      expect(bytes, orderedEquals(const [3, 1, 4, 1, 5]));
    },
  );
}
