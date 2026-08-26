import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_cache/src/metadata/tag_text_encoding.dart';

void main() {
  group('looksLikeUtf8', () {
    test('纯 ASCII 不算 —— 两种编码解出来一样，判定没有意义', () {
      expect(looksLikeUtf8(ascii.encode('Hello World')), isFalse);
    });

    test('中文 UTF-8 字节算', () {
      expect(looksLikeUtf8(utf8.encode('爱情好无奈')), isTrue);
    });

    test('真正的 Latin-1 单字节高位不算', () {
      // 'é' = 0xE9，后面没有续字节，不是合法 UTF-8。
      expect(looksLikeUtf8([0x43, 0x61, 0x66, 0xe9]), isFalse);
    });

    test('过长编码不算', () {
      // 0xC0 0xAF 是 '/' 的过长编码，合法解码器必须拒绝。
      expect(looksLikeUtf8([0xc0, 0xaf]), isFalse);
    });

    test('截断的多字节序列不算', () {
      final bytes = utf8.encode('爱').sublist(0, 2);
      expect(looksLikeUtf8(bytes), isFalse);
    });
  });

  group('decodeTagBytes', () {
    test('声明 Latin-1 但字节是 UTF-8 时按 UTF-8 解', () {
      final bytes = utf8.encode('爱情好无奈');
      expect(decodeTagBytes(bytes, declaredLatin1: true), '爱情好无奈');
    });

    test('真正的 Latin-1 仍按 Latin-1 解', () {
      expect(
        decodeTagBytes([0x43, 0x61, 0x66, 0xe9], declaredLatin1: true),
        'Café',
      );
    });

    test('声明 UTF-8 时直接按 UTF-8 解', () {
      expect(decodeTagBytes(utf8.encode('六哲'), declaredLatin1: false), '六哲');
    });
  });

  group('repairMojibake', () {
    test('修复截图里那条：UTF-8 字节被当成 Latin-1 读出来', () {
      final broken = latin1.decode(utf8.encode('爱情好无奈'));
      // 先确认构造出来的确实是用户看到的那种乱码，而不是测试自己写错了。
      expect(broken, isNot('爱情好无奈'));
      expect(broken.startsWith('ç'), isTrue);
      expect(repairMojibake(broken), '爱情好无奈');
    });

    test('正常中文不动', () {
      expect(repairMojibake('爱情好无奈'), '爱情好无奈');
    });

    test('纯 ASCII 不动', () {
      expect(repairMojibake('Bohemian Rhapsody'), 'Bohemian Rhapsody');
    });

    test('真正的 Latin-1 重音字不动', () {
      expect(repairMojibake('Café del Mar'), 'Café del Mar');
    });

    test('null 和空串安全', () {
      expect(repairMojibake(null), isNull);
      expect(repairMojibake(''), '');
    });

    test('修复是幂等的 —— 修好的字符串再跑一遍不会被二次破坏', () {
      final broken = latin1.decode(utf8.encode('六哲'));
      final fixed = repairMojibake(broken);
      expect(fixed, '六哲');
      expect(repairMojibake(fixed), '六哲');
    });
  });
}
