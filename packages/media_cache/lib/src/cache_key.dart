/// 缓存文件名使用的哈希函数。
///
/// 注意：修改这些函数的输出会让磁盘上已有的缓存文件全部失效（旧文件不会再被
/// 命中，也不会被清理），因此除非同时处理缓存迁移，否则不要改动算法。
library;

import 'dart:convert';

/// FNV-1a 32 位哈希，输入按 UTF-16 code unit 处理。
///
/// 用于封面 / 音频 / 元数据缓存的文件名。
String fnv1a32Hex(String input) {
  var hash = 0x811c9dc5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}

/// FNV-1a 64 位哈希，输入按 UTF-8 字节处理，输出补齐到 16 位十六进制。
///
/// 用于歌词缓存的文件名。
String fnv1a64Hex(String input) {
  const int offsetBasis = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  const int mask64 = 0xFFFFFFFFFFFFFFFF;
  var hash = offsetBasis;
  for (final b in utf8.encode(input)) {
    hash ^= b;
    hash = (hash * prime) & mask64;
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
