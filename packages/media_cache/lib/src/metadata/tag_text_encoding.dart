/// 标签文本的编码嗅探与「乱码」修复。
///
/// 音频标签里的编码声明经常是错的，中文文件尤其如此：ID3v2 的文本编码字节写 0
/// （按规范是 ISO-8859-1），实际塞的却是 UTF-8 字节；RIFF INFO 块干脆没有编码字段。
/// 照声明解码就会得到「爱情好无奈」→「ç±æå¥½æ å¥」这种一个汉字变三个西欧
/// 字符的结果。
library;

import 'dart:convert';
import 'dart:typed_data';

/// [bytes] 是否是一段**包含多字节序列**的合法 UTF-8。
///
/// 要求「包含多字节序列」是关键：纯 ASCII 在两种编码下解出来一模一样，没有判定
/// 价值，硬说它是 UTF-8 只会让调用方误以为嗅探生效了。
bool looksLikeUtf8(List<int> bytes) {
  var sawMultiByte = false;
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      i += 1;
      continue;
    }

    final int extra;
    final int min;
    if (b >= 0xc2 && b <= 0xdf) {
      extra = 1;
      min = 0x80;
    } else if (b >= 0xe0 && b <= 0xef) {
      extra = 2;
      min = 0x800;
    } else if (b >= 0xf0 && b <= 0xf4) {
      extra = 3;
      min = 0x10000;
    } else {
      // 0xc0/0xc1 是过长编码，0xf5 以上超出 Unicode 范围，0x80-0xbf 不能起头。
      return false;
    }
    if (i + extra >= bytes.length) return false;

    var code = b & (0x7f >> extra);
    for (var k = 1; k <= extra; k++) {
      final next = bytes[i + k];
      if (next < 0x80 || next > 0xbf) return false;
      code = (code << 6) | (next & 0x3f);
    }
    // 过长编码和代理区都算非法，否则「合法 UTF-8」的判定会松到没有意义。
    if (code < min) return false;
    if (code >= 0xd800 && code <= 0xdfff) return false;
    if (code > 0x10ffff) return false;

    sawMultiByte = true;
    i += extra + 1;
  }
  return sawMultiByte;
}

/// 按声明的 [declaredLatin1] 解码，但先嗅探一次 UTF-8。
///
/// 声明是 Latin-1 而字节其实是合法 UTF-8 时，几乎可以肯定是打标签的软件按本地
/// 编码写进去的 —— 真正的 Latin-1 文本极少能凑巧构成合法的多字节 UTF-8 序列。
String decodeTagBytes(List<int> bytes, {required bool declaredLatin1}) {
  if (bytes.isEmpty) return '';
  if (!declaredLatin1) return utf8.decode(bytes, allowMalformed: true);
  if (looksLikeUtf8(bytes)) return utf8.decode(bytes, allowMalformed: true);
  return latin1.decode(bytes, allowInvalid: true);
}

/// 修复已经解错的字符串：UTF-8 字节被当成 Latin-1 读出来的那种乱码。
///
/// 用于我们拿不到原始字节的场合 —— 比如 `audio_metadata_reader` 已经把 RIFF
/// INFO / ID3 解成 String 了，只能反向推。做法是把字符按 Latin-1 编回字节再用
/// UTF-8 严格解码：不是这种乱码的话某一步一定会失败，原样返回。
///
/// 误伤的前提是一段**真的**用 Latin-1 写的文本，恰好又构成合法的多字节 UTF-8
/// 序列（`Ã©`、`â€™` 之类）。这些组合本身几乎只在乱码里出现，所以实践中安全。
String? repairMojibake(String? value) {
  if (value == null || value.isEmpty) return value;

  final bytes = Uint8List(value.length);
  var sawHighByte = false;
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    // 有任何字符超出单字节范围，就说明它不是「被当成 Latin-1 读出来的字节流」。
    if (unit > 0xff) return value;
    if (unit >= 0x80) sawHighByte = true;
    bytes[i] = unit;
  }
  if (!sawHighByte) return value;
  if (!looksLikeUtf8(bytes)) return value;

  try {
    final decoded = utf8.decode(bytes);
    return decoded.isEmpty ? value : decoded;
  } catch (_) {
    return value;
  }
}
