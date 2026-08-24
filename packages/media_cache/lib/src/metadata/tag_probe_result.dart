import 'dart:typed_data';

class TagProbeResult {
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final String? format;
  final Uint8List? artwork;
  final String? lyrics;
  final int? trackNumber;
  final int? discNumber;

  const TagProbeResult({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.fileSize,
    this.format,
    this.artwork,
    this.lyrics,
    this.trackNumber,
    this.discNumber,
  });
}
