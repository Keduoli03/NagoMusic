import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cache/cache_manager.dart';
import '../core/database/database_helper.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../models/music_entity.dart';
import '../utils/remote_metadata_helper.dart';

class TagResult {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;
  final String? lyrics;
  final Duration? duration;
  TagResult({this.title, this.artist, this.album, this.artwork, this.lyrics, this.duration});
}

class TagProbeService {
  static final Map<String, Future<TagResult?>> _inflightProbes = {};
  
  // Artwork Cache
  static final Map<String, Uint8List> _artworkMemoryCache = {};
  static final Map<String, Future<Uint8List?>> _artworkLoading = {};
  static const int _maxArtworkCacheSize = 50;

  static Uint8List? getCachedArtwork(String id) {
    return _artworkMemoryCache[id];
  }

  static Future<Uint8List?> loadArtwork(MusicEntity song) {
    final id = song.id;
    if (_artworkMemoryCache.containsKey(id)) {
      return Future.value(_artworkMemoryCache[id]);
    }
    if (song.artwork != null && song.artwork!.isNotEmpty) {
      _putMemoryCache(id, song.artwork!);
      return Future.value(song.artwork);
    }

    if (_artworkLoading.containsKey(id)) {
      return _artworkLoading[id]!;
    }

    final future = _loadArtworkInternal(song);
    _artworkLoading[id] = future;
    future.whenComplete(() => _artworkLoading.remove(id));
    return future;
  }

  static Future<Uint8List?> _loadArtworkInternal(MusicEntity song) async {
    final localPath = song.localCoverPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _putMemoryCache(song.id, bytes);
            return bytes;
          }
        } catch (_) {}
      }
    }

    // Fallback to probe
    if (!song.isLocal) return null;
    final result = await TagProbeService().probeSongDedup(song);
    final artwork = result?.artwork;
    if (artwork != null && artwork.isNotEmpty) {
      _putMemoryCache(song.id, artwork);
      return artwork;
    }
    return null;
  }

  static void _putMemoryCache(String id, Uint8List bytes) {
    if (_artworkMemoryCache.length >= _maxArtworkCacheSize) {
      _artworkMemoryCache.remove(_artworkMemoryCache.keys.first);
    }
    _artworkMemoryCache[id] = bytes;
  }

  static void clearMemoryCache(String id) {
    _artworkMemoryCache.remove(id);
    _artworkLoading.remove(id);
  }

  Future<TagResult?> probeSong(MusicEntity song) async {
    final uriStr = song.uri;
    if (uriStr == null) return null;
    final uri = _parseSafeUri(uriStr);
    if (uri == null) return null;
    if (song.isLocal) {
      final localPath = uri.isScheme('file') ? uri.toFilePath() : uriStr;
      final result = await _parseViaMetadataReader(localPath);
      if (result != null) {
        if (result.artwork != null && result.artwork!.isNotEmpty) {
          _cacheLocalArtwork(song, result.artwork!);
        }
        return result;
      }
      if (uri.isScheme('content')) {
        final result = await _parseViaMetadataReader(uriStr);
        if (result != null && result.artwork != null && result.artwork!.isNotEmpty) {
          _cacheLocalArtwork(song, result.artwork!);
        }
        return result;
      }
      return null;
    }
    final cache = CacheManager();
    final ext = _getExtensionFromUri(uri);
    final fileName = '${song.id.hashCode}.$ext';

    // 1. Check Audio Cache (Full File)
    try {
      final audioCachePath = await cache.getAudioCachePath();
      final audioCacheFile = File(join(audioCachePath, fileName));
      final completeFile = File('${audioCacheFile.path}.complete');
      if (await audioCacheFile.exists() && await completeFile.exists()) {
        final result = await _parseViaMetadataReader(audioCacheFile.path);
        if (result != null) {
          if (result.artwork != null && result.artwork!.isNotEmpty) {
            _cacheLocalArtwork(song, result.artwork!);
          }
          return result;
        }
      }
    } catch (_) {}

    // 2. Check Tag Cache (Partial File)
    final cachePath = await cache.getTagCachePath();
    final cachedFile = File(join(cachePath, fileName));
    if (await cachedFile.exists()) {
      final cachedResult = await _parseViaMetadataReader(cachedFile.path);
      if (cachedResult != null) {
        await cachedFile.delete();
        // Partial file cannot provide accurate duration
        return TagResult(
          title: cachedResult.title,
          artist: cachedResult.artist,
          album: cachedResult.album,
          artwork: cachedResult.artwork,
          lyrics: cachedResult.lyrics,
          duration: null, 
        );
      }
      await cachedFile.delete();
    }

    const maxBytesSteps = <int>[
      2 * 1024 * 1024,
      4 * 1024 * 1024,
      8 * 1024 * 1024,
    ];
    final start = DateTime.now();
    TagResult? bestResult;

    final audioCachePath = await cache.getAudioCachePath();
    final audioCacheFile = File(join(audioCachePath, fileName));
    final audioCacheTmp = File('${audioCacheFile.path}.tmp');

    for (final maxBytes in maxBytesSteps) {
      if (DateTime.now().difference(start) >= const Duration(seconds: 20)) {
        break;
      }
      File? downloaded;
      try {
        // Try to resume from audio cache if available
        File? resumeSource;
        int resumeOffset = 0;

        if (await audioCacheTmp.exists()) {
          try {
            final size = await audioCacheTmp.length();
            if (size >= maxBytes) {
               // If cache is big enough, copy it to temp and skip download
               final tempDir = await getTemporaryDirectory();
               final ext = _getExtensionFromUri(uri);
               downloaded = File(join(tempDir.path, 'probe_cache_${DateTime.now().millisecondsSinceEpoch}.$ext'));
               await audioCacheTmp.copy(downloaded.path);
            } else if (size > 0) {
               // If cache is partial, copy it and resume download
               final tempDir = await getTemporaryDirectory();
               final ext = _getExtensionFromUri(uri);
               resumeSource = File(join(tempDir.path, 'probe_resume_${DateTime.now().millisecondsSinceEpoch}.$ext'));
               await audioCacheTmp.copy(resumeSource.path);
               resumeOffset = size;
            }
          } catch (_) {
            // Ignore cache read errors
          }
        }

        downloaded ??= await RemoteMetadataHelper.downloadPartial(
          uri,
          maxBytes: maxBytes,
          headers: song.headers,
          targetFile: resumeSource,
          startOffset: resumeOffset,
        );

        if (downloaded == null) continue;
        final result = await _parseViaMetadataReader(downloaded.path);
        if (result != null) {
          // If we have artwork, return immediately
          if (result.artwork != null && result.artwork!.isNotEmpty) {
            // If we have valid metadata, try to preserve the downloaded partial file
            // to accelerate future playback (AudioProxyServer can resume from it)
            if (await downloaded.exists()) {
              try {
                final audioCachePath = await cache.getAudioCachePath();
                final audioCacheFile = File(join(audioCachePath, fileName));
                final audioCacheTmp = File('${audioCacheFile.path}.tmp');
                
                // Only move if the audio cache tmp doesn't exist yet
                // (If it exists, player might be using it, or it might be larger)
                if (!await audioCacheTmp.exists() && !await audioCacheFile.exists()) {
                   await downloaded.rename(audioCacheTmp.path);
                   // Prevent finally block from deleting it
                   downloaded = null; 
                }
              } catch (e) {
                // Ignore move errors
              }
            }
            
            _cacheLocalArtwork(song, result.artwork!);
            return TagResult(
              title: result.title,
              artist: result.artist,
              album: result.album,
              artwork: result.artwork,
              lyrics: result.lyrics,
              duration: null, // Partial file, do not trust duration
            );
          }

          // Otherwise keep best result and try larger size
          bestResult = TagResult(
            title: result.title,
            artist: result.artist,
            album: result.album,
            artwork: result.artwork,
            lyrics: result.lyrics,
            duration: null, // Partial file, do not trust duration
          );
        }
      } finally {
        if (downloaded != null && await downloaded.exists()) {
          await Future.delayed(const Duration(milliseconds: 400));
          await downloaded.delete();
        }
      }
    }
    return bestResult;
  }

  Future<TagResult?> probeSongDedup(MusicEntity song) {
    final uriStr = song.uri;
    if (uriStr == null) return Future.value(null);
    final key = '${song.isLocal ? 'local' : 'remote'}:$uriStr';
    final existing = _inflightProbes[key];
    if (existing != null) return existing;
    final future = probeSong(song);
    _inflightProbes[key] = future;
    future.whenComplete(() {
      _inflightProbes.remove(key);
    });
    return future;
  }

  Future<void> _cacheLocalArtwork(MusicEntity song, Uint8List artwork) async {
    _putMemoryCache(song.id, artwork);
    // Check if caching is enabled
    final enabled = StorageUtil.getBoolOrDefault(
      StorageKeys.cacheLocalCover,
      defaultValue: false,
    );
    if (!enabled) return;

    try {
      final cache = CacheManager();
      final cachePath = await cache.getCoverCachePath();
      final fileName = '${song.id.hashCode}.jpg';
      final file = File(join(cachePath, fileName));
      if (await file.exists()) {
         if (song.localCoverPath != file.path) {
           await DatabaseHelper().updateSongCoverPath(song.id, file.path);
         }
         return;
      }

      var targetData = artwork;
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          artwork,
          minWidth: 1000,
          minHeight: 1000,
          quality: 85,
          format: CompressFormat.jpeg,
        );
        if (compressed.isNotEmpty) {
          targetData = compressed;
        }
      } catch (e) {
        // Fallback to original if compression fails
      }

      await file.writeAsBytes(targetData);
      
      if (song.localCoverPath != file.path) {
        await DatabaseHelper().updateSongCoverPath(song.id, file.path);
      }
    } catch (e) {
      // Ignore cache errors
    }
  }

  Future<TagResult?> _parseViaMetadataReader(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      
      final metadata = readMetadata(file, getImage: true);
      final title = metadata.title?.trim();
      final artist = metadata.artist?.trim();
      final album = metadata.album?.trim();
      
      Uint8List? artwork;
      if (metadata.pictures.isNotEmpty) {
        artwork = metadata.pictures.first.bytes;
      }

      final rawLyrics = metadata.lyrics;
      String? normalizedLyrics;
      if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
        normalizedLyrics = _dedupeLyricsContent(rawLyrics);
      }
      return TagResult(
        title: title?.isNotEmpty == true ? title : null,
        artist: artist?.isNotEmpty == true ? artist : null,
        album: album?.isNotEmpty == true ? album : null,
        artwork: artwork?.isNotEmpty == true ? artwork : null,
        lyrics: normalizedLyrics,
        duration: metadata.duration,
      );
    } catch (_) {
      return null;
    }
  }

  String _dedupeLyricsContent(String content) {
    final normalized = content.replaceFirst(RegExp('^\uFEFF'), '');
    final collapsed = _collapseRepeated(normalized);
    return _collapseAdjacent(collapsed);
  }

  String _collapseAdjacent(String content) {
    if (content.isEmpty) return content;
    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.length < 2) return content;
    final out = <String>[];
    String? last;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        out.add(line);
        last = null;
        continue;
      }
      if (t == last) continue;
      out.add(line);
      last = t;
    }
    return out.join('\n');
  }

  String _collapseRepeated(String content) {
    final t = content.trim().replaceFirst(RegExp('^\uFEFF'), '');
    if (t.isEmpty) return content;
    final lines = t.split(RegExp(r'\r?\n'));
    final check = lines.map((e) => e.trim()).toList();
    final n = lines.length;
    if (n < 2) return content;
    final pi = List<int>.filled(n, 0);
    for (int i = 1; i < n; i++) {
      var j = pi[i - 1];
      while (j > 0 && check[i] != check[j]) {
        j = pi[j - 1];
      }
      if (check[i] == check[j]) {
        j++;
      }
      pi[i] = j;
    }
    final period = n - pi[n - 1];
    if (period > 0 && n % period == 0 && n ~/ period >= 2) {
      return lines.sublist(0, period).join('\n');
    }
    return content;
  }

  String _getExtensionFromUri(Uri uri) {
    final path = uri.path;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot >= path.length - 1) return 'mp3';
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'mp3' : ext;
  }

  Uri? _parseSafeUri(String uriStr) {
    final raw = uriStr.trim();
    if (raw.isEmpty) return null;
    if (raw.contains(' ')) {
      return Uri.tryParse(Uri.encodeFull(raw));
    }
    return Uri.tryParse(raw);
  }
}

