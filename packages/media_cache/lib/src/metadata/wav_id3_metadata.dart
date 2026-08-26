import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tag_text_encoding.dart';

class WavId3Metadata {
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;
  final String? lyrics;
  final int? trackNumber;
  final int? discNumber;

  const WavId3Metadata({
    this.title,
    this.artist,
    this.album,
    this.artwork,
    this.lyrics,
    this.trackNumber,
    this.discNumber,
  });
}

class WavTechnicalMetadata {
  final int? durationMs;
  final int? bitrate;
  final int? sampleRate;

  const WavTechnicalMetadata({this.durationMs, this.bitrate, this.sampleRate});
}

/// Reads the WAV fmt/data headers without requiring the audio payload.
WavTechnicalMetadata? extractWavTechnicalMetadata(String path) {
  RandomAccessFile? reader;
  try {
    reader = File(path).openSync();
    final fileLength = reader.lengthSync();
    if (fileLength < 12 || !_hasWavHeader(reader.readSync(12))) return null;

    int? byteRate;
    int? sampleRate;
    int? dataSize;
    var offset = 12;
    while (offset + 8 <= fileLength) {
      reader.setPositionSync(offset);
      final chunkHeader = reader.readSync(8);
      if (chunkHeader.length != 8) break;
      final chunkId = ascii.decode(
        chunkHeader.sublist(0, 4),
        allowInvalid: true,
      );
      final chunkSize = ByteData.sublistView(
        chunkHeader,
        4,
        8,
      ).getUint32(0, Endian.little);
      final dataOffset = offset + 8;

      if (chunkId == 'fmt ' &&
          chunkSize >= 12 &&
          dataOffset + 12 <= fileLength) {
        final fmt = reader.readSync(12);
        sampleRate = ByteData.sublistView(
          fmt,
          4,
          8,
        ).getUint32(0, Endian.little);
        byteRate = ByteData.sublistView(fmt, 8, 12).getUint32(0, Endian.little);
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        break;
      }

      final dataEnd = dataOffset + chunkSize;
      if (dataEnd > fileLength) break;
      offset = dataEnd + (chunkSize.isOdd ? 1 : 0);
    }

    final durationMs = byteRate != null && byteRate > 0 && dataSize != null
        ? (dataSize * 1000 / byteRate).round()
        : null;
    if (durationMs == null && byteRate == null && sampleRate == null) {
      return null;
    }
    return WavTechnicalMetadata(
      durationMs: durationMs,
      bitrate: byteRate != null && byteRate > 0 ? byteRate * 8 : null,
      sampleRate: sampleRate,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      reader?.closeSync();
    } catch (_) {}
  }
}

/// Reads an ID3v2 tag stored in a WAV `id3 ` chunk.
///
/// WAV metadata is commonly placed after the audio data. The package RIFF
/// parser only handles LIST/INFO chunks, so seek through chunk headers and
/// decode the embedded ID3 tag separately.
WavId3Metadata? extractWavId3Metadata(
  String path, {
  required bool includeArtwork,
}) {
  RandomAccessFile? reader;
  try {
    reader = File(path).openSync();
    final fileLength = reader.lengthSync();
    if (fileLength < 12) return null;

    if (!_hasWavHeader(reader.readSync(12))) return null;

    var offset = 12;
    while (offset + 8 <= fileLength) {
      reader.setPositionSync(offset);
      final chunkHeader = reader.readSync(8);
      if (chunkHeader.length != 8) return null;

      final chunkId = ascii.decode(
        chunkHeader.sublist(0, 4),
        allowInvalid: true,
      );
      final chunkSize = ByteData.sublistView(
        chunkHeader,
        4,
        8,
      ).getUint32(0, Endian.little);
      final dataOffset = offset + 8;
      final dataEnd = dataOffset + chunkSize;
      if (dataEnd > fileLength) return null;

      if (chunkId.toLowerCase() == 'id3 ') {
        // Avoid allocating an unreasonable amount of memory for a malformed
        // chunk. Artwork-bearing ID3 tags are normally far below this limit.
        if (chunkSize < 10 || chunkSize > 64 * 1024 * 1024) return null;
        final tagBytes = reader.readSync(chunkSize);
        if (tagBytes.length != chunkSize) return null;
        return _parseId3Tag(tagBytes, includeArtwork: includeArtwork);
      }

      offset = dataEnd + (chunkSize.isOdd ? 1 : 0);
    }
  } catch (_) {
    return null;
  } finally {
    try {
      reader?.closeSync();
    } catch (_) {}
  }
  return null;
}

/// Finds an ID3 tag inside a downloaded tail range that has no RIFF header.
WavId3Metadata? extractWavId3MetadataFromTail(
  String path, {
  required bool includeArtwork,
}) {
  try {
    final bytes = File(path).readAsBytesSync();
    for (var offset = 0; offset + 10 <= bytes.length; offset++) {
      if (bytes[offset] != 0x49 ||
          bytes[offset + 1] != 0x44 ||
          bytes[offset + 2] != 0x33) {
        continue;
      }
      final tagSize = _synchsafeInt(bytes, offset + 6) + 10;
      if (tagSize < 10 || offset + tagSize > bytes.length) continue;
      final parsed = _parseId3Tag(
        Uint8List.sublistView(bytes, offset, offset + tagSize),
        includeArtwork: includeArtwork,
      );
      if (parsed != null) return parsed;
    }
  } catch (_) {
    return null;
  }
  return null;
}

bool _hasWavHeader(Uint8List bytes) {
  return bytes.length == 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE';
}

WavId3Metadata? _parseId3Tag(
  Uint8List tagBytes, {
  required bool includeArtwork,
}) {
  try {
    if (tagBytes.length < 10 ||
        ascii.decode(tagBytes.sublist(0, 3), allowInvalid: true) != 'ID3') {
      return null;
    }

    final version = tagBytes[3];
    if (version != 3 && version != 4) return null;
    final declaredSize = _synchsafeInt(tagBytes, 6);
    final tagEnd = (declaredSize + 10).clamp(10, tagBytes.length);
    var offset = 10;
    if ((tagBytes[5] & 0x40) != 0) {
      if (offset + 4 > tagEnd) return null;
      final extendedSize = version == 4
          ? _synchsafeInt(tagBytes, offset)
          : _uint32be(tagBytes, offset) + 4;
      if (extendedSize < 4 || offset + extendedSize > tagEnd) return null;
      offset += extendedSize;
    }

    String? title;
    String? artist;
    String? albumArtist;
    String? album;
    Uint8List? artwork;
    String? lyrics;
    int? trackNumber;
    int? discNumber;
    final tagUnsynchronized = (tagBytes[5] & 0x80) != 0;

    while (offset + 10 <= tagEnd) {
      final idBytes = tagBytes.sublist(offset, offset + 4);
      if (idBytes.every((byte) => byte == 0)) break;
      final frameId = ascii.decode(idBytes, allowInvalid: true);
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

      final frameSize = version == 4
          ? _synchsafeInt(tagBytes, offset + 4)
          : _uint32be(tagBytes, offset + 4);
      final contentStart = offset + 10;
      final contentEnd = contentStart + frameSize;
      if (frameSize <= 0 || contentEnd > tagEnd) break;

      var content = Uint8List.sublistView(tagBytes, contentStart, contentEnd);
      if (tagUnsynchronized) content = _deUnsynchronize(content);

      switch (frameId) {
        case 'TIT2':
          title ??= _decodeTextFrame(content);
        case 'TPE1':
          artist ??= _decodeTextFrame(content);
        case 'TPE2':
          albumArtist ??= _decodeTextFrame(content);
        case 'TALB':
          album ??= _decodeTextFrame(content);
        case 'TRCK':
          trackNumber ??= _parsePosition(_decodeTextFrame(content));
        case 'TPOS':
          discNumber ??= _parsePosition(_decodeTextFrame(content));
        case 'USLT':
          lyrics ??= _decodeLyricsFrame(content);
        case 'TXXX':
          final field = _decodeUserTextFrame(content);
          if (field != null &&
              field.$1.toUpperCase().contains('LYRIC') &&
              field.$2.trim().isNotEmpty) {
            lyrics ??= field.$2.trim();
          }
        case 'APIC':
          if (includeArtwork && artwork == null) {
            artwork = _decodePictureFrame(content);
          }
      }

      offset = contentEnd;
    }

    final result = WavId3Metadata(
      title: title,
      artist: albumArtist ?? artist,
      album: album,
      artwork: artwork,
      lyrics: lyrics,
      trackNumber: trackNumber,
      discNumber: discNumber,
    );
    final hasValue =
        result.title != null ||
        result.artist != null ||
        result.album != null ||
        result.artwork != null ||
        result.lyrics != null ||
        result.trackNumber != null ||
        result.discNumber != null;
    return hasValue ? result : null;
  } catch (_) {
    return null;
  }
}

int _synchsafeInt(Uint8List bytes, int offset) {
  return ((bytes[offset] & 0x7f) << 21) |
      ((bytes[offset + 1] & 0x7f) << 14) |
      ((bytes[offset + 2] & 0x7f) << 7) |
      (bytes[offset + 3] & 0x7f);
}

int _uint32be(Uint8List bytes, int offset) {
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 4,
  ).getUint32(0, Endian.big);
}

Uint8List _deUnsynchronize(Uint8List bytes) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    out.addByte(bytes[i]);
    if (bytes[i] == 0xff && i + 1 < bytes.length && bytes[i + 1] == 0) {
      i++;
    }
  }
  return out.toBytes();
}

String? _decodeTextFrame(Uint8List content) {
  if (content.isEmpty) return null;
  final value = _decodeText(content.sublist(1), content.first).trim();
  return value.isEmpty ? null : value;
}

int? _parsePosition(String? value) {
  if (value == null) return null;
  return int.tryParse(value.split('/').first.trim());
}

String? _decodeLyricsFrame(Uint8List content) {
  if (content.length < 5) return null;
  final encoding = content.first;
  final descriptionStart = 4;
  final descriptionEnd = _findTerminator(content, descriptionStart, encoding);
  final lyricsStart = descriptionEnd + _terminatorLength(encoding);
  if (lyricsStart > content.length) return null;
  final value = _decodeText(content.sublist(lyricsStart), encoding).trim();
  return value.isEmpty ? null : value;
}

(String, String)? _decodeUserTextFrame(Uint8List content) {
  if (content.length < 2) return null;
  final encoding = content.first;
  final descriptionEnd = _findTerminator(content, 1, encoding);
  final valueStart = descriptionEnd + _terminatorLength(encoding);
  if (valueStart > content.length) return null;
  return (
    _decodeText(content.sublist(1, descriptionEnd), encoding),
    _decodeText(content.sublist(valueStart), encoding),
  );
}

Uint8List? _decodePictureFrame(Uint8List content) {
  if (content.length < 5) return null;
  final encoding = content.first;
  final mimeEnd = content.indexOf(0, 1);
  if (mimeEnd < 0 || mimeEnd + 2 >= content.length) return null;
  final descriptionStart = mimeEnd + 2;
  final descriptionEnd = _findTerminator(content, descriptionStart, encoding);
  final imageStart = descriptionEnd + _terminatorLength(encoding);
  if (imageStart >= content.length) return null;
  return Uint8List.fromList(content.sublist(imageStart));
}

int _findTerminator(Uint8List bytes, int start, int encoding) {
  if (encoding == 1 || encoding == 2) {
    for (var i = start; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return bytes.length;
  }
  final end = bytes.indexOf(0, start);
  return end < 0 ? bytes.length : end;
}

int _terminatorLength(int encoding) {
  return encoding == 1 || encoding == 2 ? 2 : 1;
}

String _decodeText(Uint8List bytes, int encoding) {
  if (bytes.isEmpty) return '';
  if (encoding == 1 || encoding == 2) {
    var offset = 0;
    var endian = encoding == 2 ? Endian.big : Endian.little;
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      offset = 2;
      endian = Endian.little;
    } else if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      offset = 2;
      endian = Endian.big;
    }

    final units = <int>[];
    final data = ByteData.sublistView(bytes);
    while (offset + 1 < bytes.length) {
      final unit = data.getUint16(offset, endian);
      if (unit == 0) break;
      units.add(unit);
      offset += 2;
    }
    return String.fromCharCodes(units);
  }

  final end = bytes.indexOf(0);
  final value = end < 0 ? bytes : bytes.sublist(0, end);
  // encoding 3 声明 UTF-8；0 声明 ISO-8859-1，但中文标签软件经常在这里写 UTF-8
  // 字节，所以交给 decodeTagBytes 嗅探，不能照着声明硬解。
  return decodeTagBytes(value, declaredLatin1: encoding != 3);
}
