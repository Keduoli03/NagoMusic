import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:media_cache/media_cache.dart';
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
      final name = fnv1a32Hex(key);
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

  /// Returns the cached artwork path for [key] if it already exists on disk,
  /// without fetching or recompressing. Lets callers skip redundant downloads.
  static Future<String?> cachedPathIfExists({required String key}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      final name = fnv1a32Hex(key);
      final target = File(p.join(cacheDir.path, '$name.jpg'));
      if (await target.exists()) return target.path;
    } catch (_) {}
    return null;
  }

  static Future<void> removeCachedArtwork({required String key}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      final name = fnv1a32Hex(key);
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
}
