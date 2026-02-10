import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/network/http_utils.dart';
import '../models/music_entity.dart';

class RemoteMetadata {
  final int? fileSize;
  final int? bitrate;
  final int? sampleRate;
  final String? format;
  final Duration? duration;

  RemoteMetadata({
    this.fileSize,
    this.bitrate,
    this.sampleRate,
    this.format,
    this.duration,
  });
}

class RemoteMetadataHelper {
  static Future<RemoteMetadata> fetch(MusicEntity song) async {
    if (song.isLocal || song.uri == null) {
      return RemoteMetadata();
    }

    final dio = Dio();
    final uri = Uri.parse(song.uri!);
    
    // Prepare headers
    final options = Options(
      headers: song.headers != null ? Map<String, dynamic>.from(song.headers!) : {},
      responseType: ResponseType.stream,
    );
    
    // Add Range header for first 256KB to get header + Content-Range
    options.headers!['Range'] = 'bytes=0-${256 * 1024 - 1}';

    try {
      final response = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: options,
      );

      // Parse File Size from Content-Range or Content-Length
      int? totalSize;
      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        // Format: bytes 0-262143/1234567
        final parts = contentRange.split('/');
        if (parts.length == 2) {
          totalSize = int.tryParse(parts[1]);
        }
      } else {
        // Fallback to content-length if range is ignored (server returns full file)
        final contentLength = response.headers.value('content-length');
        if (contentLength != null) {
          totalSize = int.tryParse(contentLength);
        }
      }

      // Write stream to temp file
      final tempDir = await getTemporaryDirectory();
      final ext = p.extension(uri.path);
      final tempFile = File(p.join(tempDir.path, 'probe_${DateTime.now().millisecondsSinceEpoch}$ext'));
      
      final sink = tempFile.openWrite();
      final stream = response.data!.stream;
      
      int bytesWritten = 0;
      await for (final chunk in stream) {
        sink.add(chunk);
        bytesWritten += chunk.length;
        if (bytesWritten >= 256 * 1024) {
          // If we got more than expected (server ignored range), stop early
          // We must cancel the stream to close the connection
          break; 
        }
      }
      await sink.close();

      // Read Metadata
      AudioMetadata? metadata;
      try {
        metadata = readMetadata(tempFile, getImage: false);
      } catch (e) {
        // Metadata reading failed (maybe incomplete file or format not supported)
      } finally {
        // Cleanup
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      return RemoteMetadata(
        fileSize: totalSize,
        bitrate: metadata?.bitrate,
        sampleRate: metadata?.sampleRate,
        format: ext.replaceAll('.', '').toUpperCase(),
        duration: metadata?.duration,
      );

    } catch (e) {
      return RemoteMetadata();
    }
  }

  static Future<File?> downloadPartial(
    Uri uri, {
    int maxBytes = 256 * 1024,
    Map<String, String>? headers,
    File? targetFile,
    int startOffset = 0,
  }) async {
    final dio = Dio();
    final options = Options(
      headers: headers != null ? Map<String, dynamic>.from(headers) : {},
      responseType: ResponseType.stream,
    );
    
    options.headers!['Range'] = 'bytes=$startOffset-${maxBytes - 1}';

    try {
      final response = await HttpUtils.fetchWithManualRedirect<ResponseBody>(
        dio,
        uri,
        options: options,
      );

      File file;
      if (targetFile != null) {
        file = targetFile;
      } else {
        final tempDir = await getTemporaryDirectory();
        final ext = p.extension(uri.path);
        file = File(p.join(tempDir.path, 'probe_${DateTime.now().millisecondsSinceEpoch}$ext'));
      }
      
      final sink = file.openWrite(mode: targetFile != null ? FileMode.append : FileMode.write);
      final stream = response.data!.stream;
      
      int bytesWritten = 0;
      await for (final chunk in stream) {
        sink.add(chunk);
        bytesWritten += chunk.length;
        // Check if we exceeded the range (servers might ignore range and send full file)
        // But we only care about reaching maxBytes total (including startOffset)
        if (startOffset + bytesWritten >= maxBytes) {
          break; 
        }
      }
      await sink.close();
      return file;
    } catch (e) {
      return null;
    }
  }
}
