import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> getCoverPath(String songId) async {
    final path = await _localPath;
    final coversDir = Directory(join(path, 'covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    // Sanitize songId to be a valid filename
    final filename = '${songId.replaceAll(RegExp(r'[^\w\d]'), '_')}.jpg';
    return join(coversDir.path, filename);
  }

  Future<String> getCoverCachePath() async {
    final path = await _localPath;
    final coversDir = Directory(join(path, 'covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir.path;
  }

  Future<String> getAudioCachePath() async {
     final directory = await getTemporaryDirectory(); // Use temp for audio cache
     final cacheDir = Directory(join(directory.path, 'audio_cache'));
     if (!await cacheDir.exists()) {
       await cacheDir.create(recursive: true);
     }
     return cacheDir.path;
  }

  Future<String> getTagCachePath() async {
    final directory = await getTemporaryDirectory();
    final cacheDir = Directory(join(directory.path, 'tag_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  Future<File?> saveCoverImage(String songId, List<int> bytes) async {
    try {
      final path = await getCoverPath(songId);
      final file = File(path);
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      return null;
    }
  }

  Future<bool> hasCover(String songId) async {
    final path = await getCoverPath(songId);
    return File(path).exists();
  }

  Future<int> getDirectorySize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<int> getAudioCacheSize() async {
    final path = await getAudioCachePath();
    return getDirectorySize(path);
  }

  Future<int> getCoverCacheSize() async {
    final path = await getCoverCachePath();
    return getDirectorySize(path);
  }

  Future<void> clearAudioCache() async {
    final path = await getAudioCachePath();
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> clearTagCache() async {
    final path = await getTagCachePath();
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> clearCoverCache() async {
    final path = await getCoverCachePath();
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> clearAllCache() async {
    await clearAudioCache();
    await clearCoverCache();
    await clearTagCache();
  }

  Future<void> trimAudioCache(int maxBytes, {Set<String> excludePaths = const {}}) async {
    if (maxBytes <= 0) return;
    final path = await getAudioCachePath();
    final dir = Directory(path);
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && !excludePaths.contains(entity.path)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var total = 0;
    for (final f in files) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    for (final f in files) {
      if (total <= maxBytes) break;
      try {
        final len = await f.length();
        await f.delete();
        total -= len;
      } catch (_) {}
    }
  }

  Future<void> trimAllCache(int maxBytes, {Set<String> excludePaths = const {}}) async {
    if (maxBytes <= 0) return;
    final audioPath = await getAudioCachePath();
    final coverPath = await getCoverCachePath();
    final files = <File>[];
    for (final path in [audioPath, coverPath]) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && !excludePaths.contains(entity.path)) {
          files.add(entity);
        }
      }
    }
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var total = 0;
    for (final f in files) {
      try {
        total += await f.length();
      } catch (_) {}
    }
    for (final f in files) {
      if (total <= maxBytes) break;
      try {
        final len = await f.length();
        await f.delete();
        total -= len;
      } catch (_) {}
    }
  }
}
