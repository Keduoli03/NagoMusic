import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Result of parsing an OGG (Vorbis/Opus) Vorbis-comment header.
class OggCommentResult {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;
  final String? lyrics;

  const OggCommentResult({
    this.title,
    this.artist,
    this.album,
    this.artwork,
    this.lyrics,
  });
}

/// True for OGG-family extensions (`.ogg`, `.oga`, `.opus`, and the `.0gg` typo).
bool isOggPath(String path) {
  var ext = p.extension(path).toLowerCase();
  if (ext == '.0gg') ext = '.ogg';
  return ext == '.ogg' || ext == '.oga' || ext == '.opus';
}

/// Self-contained OGG (Vorbis/Opus) Vorbis-comment extractor.
///
/// The bundled `audio_metadata_reader` OGG path is fragile: it only reads the
/// first two pages, throws on truncated files, and frequently misses covers and
/// lyrics. This reads the OGG pages directly, reassembles the comment-header
/// packet (the 2nd packet — it can span multiple pages when a large cover is
/// embedded), and extracts TITLE/ARTIST/ALBUM, the `METADATA_BLOCK_PICTURE`
/// cover, and lyrics (`LYRICS` / `UNSYNCEDLYRICS` / `LYRICS-*`).
///
/// Tolerant of truncated/partial files (remote probes): it returns whatever it
/// managed to parse, or null if no comment packet was found.
///
/// Synchronous — call it from a background isolate for large files.
OggCommentResult? extractOggVorbisComments(
  String path, {
  required bool includeArtwork,
}) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    // Collect the first two complete packets: [0] = id header, [1] = comment.
    final packets = <List<int>>[];
    var current = <int>[];
    const maxRead = 40 * 1024 * 1024; // safety cap for absurd covers
    var totalRead = 0;

    outer:
    while (totalRead < maxRead) {
      final header = raf.readSync(27);
      if (header.length < 27) break;
      // "OggS" capture pattern
      if (header[0] != 0x4F ||
          header[1] != 0x67 ||
          header[2] != 0x67 ||
          header[3] != 0x53) {
        break;
      }
      final numSegments = header[26];
      final segTable = raf.readSync(numSegments);
      if (segTable.length < numSegments) break;
      var dataLen = 0;
      for (final s in segTable) {
        dataLen += s;
      }
      final pageData = raf.readSync(dataLen);
      if (pageData.length < dataLen) break;
      totalRead += 27 + numSegments + dataLen;

      var pos = 0;
      for (var i = 0; i < numSegments; i++) {
        final seg = segTable[i];
        if (seg > 0) {
          current.addAll(pageData.sublist(pos, pos + seg));
          pos += seg;
        }
        if (seg < 255) {
          // A lacing value < 255 terminates a packet.
          packets.add(current);
          current = <int>[];
          if (packets.length >= 2) break outer;
        }
      }
    }

    if (packets.length < 2) return null;
    final comment = packets[1];
    if (comment.length < 8) return null;

    // Locate the start of the vorbis-comment structure within the packet.
    int offset;
    // Vorbis: 0x03 'v' 'o' 'r' 'b' 'i' 's'
    if (comment[0] == 0x03 &&
        comment[1] == 0x76 &&
        comment[2] == 0x6F &&
        comment[3] == 0x72 &&
        comment[4] == 0x62 &&
        comment[5] == 0x69 &&
        comment[6] == 0x73) {
      offset = 7;
    } else if (String.fromCharCodes(comment.sublist(0, 8)) == 'OpusTags') {
      offset = 8;
    } else {
      return null;
    }

    int o = offset;
    if (o + 4 > comment.length) return null;
    final vendorLen = _readUint32LE(comment, o);
    o += 4 + vendorLen;
    if (o + 4 > comment.length) return null;
    final count = _readUint32LE(comment, o);
    o += 4;

    String? title;
    String? artist;
    String? album;
    String? lyrics;
    Uint8List? artwork;

    for (var i = 0; i < count; i++) {
      if (o + 4 > comment.length) break;
      final len = _readUint32LE(comment, o);
      o += 4;
      if (len < 0 || o + len > comment.length) break; // truncated/partial file
      final entry = comment.sublist(o, o + len);
      o += len;

      final eq = entry.indexOf(0x3D); // '='
      if (eq <= 0) continue;
      final key = String.fromCharCodes(entry.sublist(0, eq)).toUpperCase();
      final valueBytes = entry.sublist(eq + 1);

      switch (key) {
        case 'TITLE':
          title ??= _decodeUtf8(valueBytes);
          break;
        case 'ARTIST':
        case 'ALBUMARTIST':
          artist ??= _decodeUtf8(valueBytes);
          break;
        case 'ALBUM':
          album ??= _decodeUtf8(valueBytes);
          break;
        case 'LYRICS':
        case 'UNSYNCEDLYRICS':
        case 'UNSYNCED LYRICS':
          lyrics ??= _decodeUtf8(valueBytes);
          break;
        case 'METADATA_BLOCK_PICTURE':
          if (includeArtwork && artwork == null) {
            artwork = _parseFlacPictureBlock(_decodeUtf8(valueBytes));
          }
          break;
        case 'COVERART': // legacy: raw base64 image bytes
          if (includeArtwork && artwork == null) {
            artwork = _tryDecodeBase64(_decodeUtf8(valueBytes));
          }
          break;
        default:
          if (lyrics == null && key.startsWith('LYRICS')) {
            lyrics = _decodeUtf8(valueBytes);
          }
          break;
      }
    }

    return OggCommentResult(
      title: title,
      artist: artist,
      album: album,
      artwork: artwork,
      lyrics: lyrics,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

int _readUint32LE(List<int> b, int o) {
  return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}

String _decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}

Uint8List? _tryDecodeBase64(String value) {
  try {
    final bytes = base64Decode(value.trim());
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

/// Parses a base64-encoded FLAC `METADATA_BLOCK_PICTURE` and returns the raw
/// image bytes. Internal fields are big-endian per the FLAC picture spec.
Uint8List? _parseFlacPictureBlock(String base64Value) {
  try {
    final raw = base64Decode(base64Value.trim());
    final bd = ByteData.sublistView(raw);
    var o = 0;
    o += 4; // picture type
    final mimeLen = bd.getUint32(o);
    o += 4 + mimeLen;
    final descLen = bd.getUint32(o);
    o += 4 + descLen;
    o += 16; // width, height, color depth, colors used (4 x uint32)
    final dataLen = bd.getUint32(o);
    o += 4;
    if (dataLen <= 0 || o + dataLen > raw.length) return null;
    return Uint8List.sublistView(raw, o, o + dataLen);
  } catch (_) {
    return null;
  }
}
