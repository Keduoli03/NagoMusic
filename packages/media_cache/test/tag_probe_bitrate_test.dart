import 'package:flutter_test/flutter_test.dart';
import 'package:media_cache/media_cache.dart';

void main() {
  test('estimates average bitrate when a parser does not provide one', () {
    expect(
      estimateAudioBitrate(fileSize: 4 * 1024 * 1024, durationMs: 240000),
      139810,
    );
  });

  test('does not estimate bitrate without usable size and duration', () {
    expect(estimateAudioBitrate(fileSize: null, durationMs: 240000), isNull);
    expect(estimateAudioBitrate(fileSize: 1024, durationMs: 0), isNull);
  });
}
