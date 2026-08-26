import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:media_cache/media_cache.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ArtworkCacheHelper {
  /// 压缩并缓存封面，返回缓存文件路径。
  ///
  /// 默认按 [key] 取文件名，同一个 key 已经缓存过就直接返回旧路径、不重复压缩。
  ///
  /// [replaceExisting] 用于「用户主动换了一张封面」的场景（在线匹配换图）。这时
  /// 会重新压缩，并且**换一个文件名**（名字里带上图片内容的指纹）。
  ///
  /// 换名不是洁癖，是必须的：播放页的粒子封面拿 `song.localCoverPath` 当缓存键
  /// 来决定要不要重新解码（见 particle_cover.dart 的 `_sourceKey`）。沿用同一个
  /// 路径写新图的话，路径没变、键也没变，那边就认为「封面没变」，界面会一直停在
  /// 旧图上，直到退出播放页重进。
  ///
  /// 旧文件不在这里删 —— 调用方手里才有旧路径，用
  /// [removeCachedArtworkByPath] 清理即可。按 key 删是删不掉的，新旧名字不同。
  static Future<String?> cacheCompressedArtwork({
    required Uint8List bytes,
    required String key,
    int quality = 88,
    int minSize = 1024,
    bool replaceExisting = false,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final name = replaceExisting
          ? '${fnv1a32Hex(key)}_${_contentFingerprint(bytes)}'
          : fnv1a32Hex(key);
      final target = File(p.join(cacheDir.path, '$name.jpg'));
      // 同一张图重复写没有意义，两种模式下都先看文件在不在。
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

  /// 图片内容的短指纹，只用来给换过的封面取一个不同的文件名。
  ///
  /// 不是密码学哈希也不需要是 —— 要的只是「换了图基本一定换名字」。取首尾各若干
  /// 字节加总长度，避免为一张几百 KB 的图整个遍历一遍；真撞了也只是少刷新一次，
  /// 不会损坏数据。
  static String _contentFingerprint(Uint8List bytes) {
    const sampleSize = 64;
    final head = bytes.take(sampleSize).join(',');
    final tailStart = bytes.length > sampleSize ? bytes.length - sampleSize : 0;
    final tail = bytes.skip(tailStart).join(',');
    return fnv1a32Hex('${bytes.length}|$head|$tail');
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
