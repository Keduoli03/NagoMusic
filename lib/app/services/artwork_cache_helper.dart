import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ArtworkCacheHelper {
  static Future<String?> cacheCompressedArtwork({
    required Uint8List bytes,
    required String key,
    int quality = 88,
    int minSize = 1024,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final name = _hashKey(key);
      final target = File(p.join(cacheDir.path, '$name.jpg'));
      if (await target.exists()) return target.path;
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: quality,
        minWidth: minSize,
        minHeight: minSize,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return null;
      await target.writeAsBytes(compressed, flush: true);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> removeCachedArtwork({
    required String key,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      final name = _hashKey(key);
      final target = File(p.join(cacheDir.path, '$name.jpg'));
      if (await target.exists()) {
        await target.delete();
      }
    } catch (_) {}
  }

  static Future<void> removeCachedArtworkByPath(String path) async {
    final pth = path.trim();
    if (pth.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      final normalizedPath = File(pth).absolute.path;
      final normalizedDir = cacheDir.absolute.path;
      if (!normalizedPath.startsWith(normalizedDir)) return;
      final file = File(pth);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static String _hashKey(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
