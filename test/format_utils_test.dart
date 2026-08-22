import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/utils/format_utils.dart';

void main() {
  group('formatDurationMs', () {
    test('returns placeholder for null/zero/negative', () {
      expect(formatDurationMs(null), '--:--');
      expect(formatDurationMs(0), '--:--');
      expect(formatDurationMs(-1), '--:--');
      expect(formatDurationMs(0, placeholder: '-'), '-');
    });

    test('formats as m:ss without padding minutes by default', () {
      expect(formatDurationMs(1000), '0:01');
      expect(formatDurationMs(61000), '1:01');
      expect(formatDurationMs(3661000), '61:01');
    });

    test('pads minutes and rounds seconds when asked', () {
      expect(formatDurationMs(61000, padMinutes: true), '01:01');
      expect(formatDurationMs(1500, roundSeconds: true), '0:02');
      expect(formatDurationMs(1500), '0:01');
    });
  });

  group('formatClock', () {
    test('pads both fields', () {
      expect(formatClock(const Duration(seconds: 5)), '00:05');
      expect(formatClock(const Duration(minutes: 3, seconds: 9)), '03:09');
    });

    test('null and non-positive fall back', () {
      expect(formatClock(null), '00:00');
      expect(formatClock(null, zeroText: '--:--'), '--:--');
      expect(formatClock(Duration.zero, zeroText: '00:00'), '00:00');
    });
  });

  test('formatMinutesAsClock renders h:mm', () {
    expect(formatMinutesAsClock(0), '0:00');
    expect(formatMinutesAsClock(75), '1:15');
    expect(formatMinutesAsClock(75.6), '1:16');
  });

  group('formatFileSize', () {
    test('placeholder for non-positive', () {
      expect(formatFileSize(null), '-');
      expect(formatFileSize(0), '-');
      expect(formatFileSize(0, placeholder: '0 B'), '0 B');
    });

    test('adaptive precision by default', () {
      expect(formatFileSize(512), '512.0 B');
      expect(formatFileSize(2048), '2.00 KB');
      expect(formatFileSize(20 * 1024), '20.0 KB');
    });

    test('fixed precision when requested', () {
      expect(formatFileSize(2048, fractionDigits: 2), '2.00 KB');
      expect(formatFileSize(512, fractionDigits: 2), '512.00 B');
    });
  });

  test('formatBitrate switches precision at 100 kbps', () {
    expect(formatBitrate(null), '-');
    expect(formatBitrate(0), '-');
    expect(formatBitrate(64000), '64.0 kbps');
    expect(formatBitrate(320000), '320 kbps');
  });

  test('formatSampleRate switches unit below 1000 Hz', () {
    expect(formatSampleRate(null), '-');
    expect(formatSampleRate(800), '800 Hz');
    expect(formatSampleRate(44100), '44.1 kHz');
    expect(formatSampleRate(192000), '192 kHz');
  });

  test('formatDayKey zero-pads', () {
    expect(formatDayKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(formatDayKey(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
