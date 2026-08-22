import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/state/song_state.dart';
import 'package:nagomusic/app/utils/audio_quality.dart';

SongEntity song({String? format, int? sampleRate, int? bitrate}) {
  return SongEntity(
    id: 'x',
    title: 't',
    artist: 'a',
    isLocal: true,
    format: format,
    sampleRate: sampleRate,
    bitrate: bitrate,
  );
}

void main() {
  group('audioQualityTagFor', () {
    test('high sample rate lossless is Hi-Res', () {
      final tag = audioQualityTagFor(song(format: 'FLAC', sampleRate: 96000));
      expect(tag?.tier, AudioQualityTier.hires);
      expect(tag?.label, 'Hi-Res');
    });

    test('CD-quality lossless is 无损', () {
      final tag = audioQualityTagFor(song(format: 'FLAC', sampleRate: 44100));
      expect(tag?.tier, AudioQualityTier.lossless);
      expect(tag?.label, '无损');
    });

    test('48 kHz lossless stays 无损 (boundary)', () {
      final tag = audioQualityTagFor(song(format: 'WAV', sampleRate: 48000));
      expect(tag?.tier, AudioQualityTier.lossless);
    });

    test('lossless without sample rate falls back to 无损', () {
      expect(
        audioQualityTagFor(song(format: 'APE'))?.tier,
        AudioQualityTier.lossless,
      );
    });

    test('DSD is always Hi-Res', () {
      expect(
        audioQualityTagFor(song(format: 'DSF'))?.tier,
        AudioQualityTier.hires,
      );
    });

    test('format matching is case-insensitive', () {
      expect(
        audioQualityTagFor(song(format: 'flac', sampleRate: 44100))?.tier,
        AudioQualityTier.lossless,
      );
    });

    test('320 kbps lossy is HQ', () {
      final tag = audioQualityTagFor(song(format: 'MP3', bitrate: 320000));
      expect(tag?.tier, AudioQualityTier.hq);
      expect(tag?.label, 'HQ');
    });

    test('128 kbps lossy gets no tag', () {
      expect(audioQualityTagFor(song(format: 'MP3', bitrate: 128000)), isNull);
    });

    test('m4a is treated as lossy, not ALAC', () {
      expect(
        audioQualityTagFor(song(format: 'M4A', sampleRate: 96000)),
        isNull,
      );
    });

    test('missing metadata yields no tag', () {
      expect(audioQualityTagFor(song()), isNull);
    });
  });
}
