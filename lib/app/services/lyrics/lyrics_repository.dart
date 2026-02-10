import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../state/song_state.dart';
import '../metadata/tag_probe_service.dart';

class LyricsRepository {
  Future<String?> loadLrc(SongEntity song) async {
    final embedded = await _readFromEmbeddedTags(song);
    if (embedded != null && embedded.trim().isNotEmpty) {
      await _writeToCache(song.id, embedded);
      return embedded;
    }

    final cached = await _readFromCache(song.id);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    final local = await _readFromLocalSidecar(song);
    if (local != null && local.trim().isNotEmpty) {
      await _writeToCache(song.id, local);
      return local;
    }
    return null;
  }

  Future<void> removeCachedLrc(String songId) async {
    try {
      final file = await _cacheFileForSongId(songId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> saveLrcToCache(
    String songId,
    String content, {
    bool overwrite = false,
  }) async {
    final c = content.replaceFirst('\uFEFF', '').trim();
    if (c.isEmpty) return;
    if (!overwrite) {
      final exists = await hasCachedLrc(songId);
      if (exists) return;
    }
    await _writeToCache(songId, c);
  }

  Future<bool> hasCachedLrc(String songId) async {
    try {
      final file = await _cacheFileForSongId(songId);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readFromCache(String songId) async {
    try {
      final file = await _cacheFileForSongId(songId);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToCache(String songId, String content) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final lyricsDir = Directory(p.join(dir.path, 'lyrics'));
      if (!await lyricsDir.exists()) {
        await lyricsDir.create(recursive: true);
      }
      final file = File(p.join(lyricsDir.path, '${_cacheKey(songId)}.lrc'));
      await file.writeAsString(content, flush: true);
    } catch (_) {}
  }

  Future<File> _cacheFileForSongId(String songId) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'lyrics', '${_cacheKey(songId)}.lrc'));
  }

  String _cacheKey(String songId) {
    final bytes = utf8.encode(songId);
    const int offsetBasis = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    const int mask64 = 0xFFFFFFFFFFFFFFFF;
    var hash = offsetBasis;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * prime) & mask64;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  Future<String?> _readFromEmbeddedTags(SongEntity song) async {
    final uri = (song.uri ?? '').trim();
    if (uri.isEmpty) return null;
    if (!song.isLocal) return null;
    final result = await TagProbeService.instance.probeSongDedup(
      uri: uri,
      isLocal: true,
      includeArtwork: false,
    );
    final t = (result?.lyrics ?? '').trim();
    return t.isEmpty ? null : t;
  }

  Future<String?> _readFromLocalSidecar(SongEntity song) async {
    final uri = (song.uri ?? '').trim();
    if (uri.isEmpty) return null;

    final audioFile = File(uri);
    if (!await audioFile.exists()) return null;

    final dir = p.dirname(uri);
    final base = p.basenameWithoutExtension(uri);
    final candidates = <String>[
      p.join(dir, '$base.lrc'),
      p.join(dir, '$base.LRC'),
      if (song.title.trim().isNotEmpty) p.join(dir, '${song.title}.lrc'),
      if (song.artist.trim().isNotEmpty && song.title.trim().isNotEmpty)
        p.join(dir, '${song.artist} - ${song.title}.lrc'),
      if (song.artist.trim().isNotEmpty && song.title.trim().isNotEmpty)
        p.join(dir, '${song.title} - ${song.artist}.lrc'),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      }
    }

    try {
      final entries = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.lrc')
          .toList();
      if (entries.isEmpty) return null;

      final title = song.title.trim().toLowerCase();
      final artist = song.artist.trim().toLowerCase();
      File? best;
      int bestScore = -1;
      for (final f in entries) {
        final name = p.basenameWithoutExtension(f.path).toLowerCase();
        var score = 0;
        if (title.isNotEmpty && name.contains(title)) score += 2;
        if (artist.isNotEmpty && name.contains(artist)) score += 1;
        if (score > bestScore) {
          bestScore = score;
          best = f;
        }
      }
      if (best == null || bestScore <= 0) return null;
      final bytes = await best.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}
