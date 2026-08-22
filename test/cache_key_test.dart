import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/utils/cache_key.dart';

/// 这些期望值等同于重构前各服务内联实现的输出。
/// 若因改动算法而失败，说明磁盘上已有缓存会全部失效——不要直接改期望值。
void main() {
  group('fnv1a32Hex', () {
    test('matches the previous inline implementation', () {
      expect(fnv1a32Hex(''), '811c9dc5');
      expect(fnv1a32Hex('a'), 'e40c292c');
      expect(fnv1a32Hex('foobar'), 'bf9cf968');
    });

    test('is stable and collision-free for distinct keys', () {
      expect(fnv1a32Hex('audio:song-1'), fnv1a32Hex('audio:song-1'));
      expect(fnv1a32Hex('audio:song-1'), isNot(fnv1a32Hex('audio:song-2')));
    });
  });

  group('fnv1a64Hex', () {
    test('matches the previous inline implementation', () {
      expect(fnv1a64Hex(''), '-340d631b7bdddcdb');
      expect(fnv1a64Hex('a'), '-509c23b379fe1374');
      expect(fnv1a64Hex('song-1'), '65cc51e20e89087e');
    });

    // Dart ints are signed 64-bit, so `& mask64` cannot clear the sign bit and
    // `toUnsigned(64)` is a no-op — roughly half of all keys hash to a
    // '-'-prefixed string. That is what shipped, and the on-disk lyrics cache
    // is named after it, so the quirk is preserved deliberately.
    test('keeps the signed-output quirk of the original', () {
      expect(fnv1a64Hex('歌曲'), startsWith('-'));
      expect(fnv1a64Hex('song-1'), isNot(startsWith('-')));
    });

    test('is deterministic', () {
      expect(fnv1a64Hex('song-1'), fnv1a64Hex('song-1'));
      expect(fnv1a64Hex('song-1'), isNot(fnv1a64Hex('song-2')));
    });
  });
}
