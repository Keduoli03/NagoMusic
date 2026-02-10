import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;

import '../cache/audio_cache_service.dart';
import 'tag_probe_result.dart';

/// Abstract handler for audio format probing strategies.
abstract class ProbeHandler {
  /// Returns true if this handler should be used for the given file path/extension.
  bool canHandle(String path);

  /// Executes the probing logic.
  /// 
  /// Returns a [TagProbeResult] if successful, or null if it fails or decides not to handle.
  Future<TagProbeResult?> probe({
    required Uri uri,
    required Map<String, String>? headers,
    required bool includeArtwork,
    required int? totalBytes,
    required TagProbeResult? currentBest,
    required AudioCacheService audioCache,
    required Future<TagProbeResult?> Function(File file, {required bool includeArtwork}) prober,
    required Future<File?> Function(int maxBytes) downloadPartial,
  });
}

/// Handler for formats with metadata at the start (OGG, FLAC, MP3 with ID3v2).
/// 
/// These formats usually have metadata at the start.
/// However, if artwork is large, it might exceed the initial probe size (e.g. 8MB).
/// This handler implements a "Progressive Head Expansion" strategy:
/// It continues to download larger chunks of the file until metadata is found,
/// rather than relying on a hard file size limit.
class ProgressiveHeadHandler implements ProbeHandler {
  @override
  bool canHandle(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.ogg' || 
           ext == '.0gg' || 
           ext == '.oga' || 
           ext == '.opus' ||
           ext == '.flac' ||
           ext == '.mp3';
  }

  @override
  Future<TagProbeResult?> probe({
    required Uri uri,
    required Map<String, String>? headers,
    required bool includeArtwork,
    required int? totalBytes,
    required TagProbeResult? currentBest,
    required AudioCacheService audioCache,
    required Future<TagProbeResult?> Function(File file, {required bool includeArtwork}) prober,
    required Future<File?> Function(int maxBytes) downloadPartial,
  }) async {
    // Check if we have a "good enough" result. 
    // For OGG, we really want artwork/lyrics if we requested them.
    final hasGoodResult = currentBest != null && 
        (currentBest.title != null || currentBest.artist != null) &&
        (!includeArtwork || (currentBest.artwork?.isNotEmpty ?? false));

    if (hasGoodResult) return null; // No need to fallback

    // Previous steps (in TagProbeService) tried up to 8MB.
    // We start from 16MB and double until we find tags or hit the end.
    var currentSize = 16 * 1024 * 1024;
    
    // Safety limit: e.g. 64MB. If headers are larger than 64MB, it's probably broken or insane.
    // Or we can go up to totalBytes.
    final limit = (totalBytes != null && totalBytes > 0) ? totalBytes : 100 * 1024 * 1024;

    while (currentSize <= limit) {
       final file = await downloadPartial(currentSize);
       if (file == null) break;
       
       final parsed = await prober(file, includeArtwork: includeArtwork);
       if (parsed != null) {
          // Check if this result is better
          final isBetter = (parsed.title != null || parsed.artist != null) &&
                           (!includeArtwork || (parsed.artwork?.isNotEmpty ?? false));
          
          if (isBetter) return parsed;
       }

       // If we reached the exact file size, no need to try larger
       if (totalBytes != null && currentSize >= totalBytes) break;

       currentSize *= 2;
       
       // Cap at totalBytes if we overshoot
       if (totalBytes != null && currentSize > totalBytes) {
         currentSize = totalBytes;
       }
    }
    
    return null;
  }
}
