import 'dart:convert';
import 'dart:io';

import 'package:media_cache/media_cache.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../state/song_state.dart';
import '../log/log.dart';

class LyricsRepository {
  static const String _logTag = 'LyricsRepository';

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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '删除歌词缓存失败 songId=$songId', e, s);
    }
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '检查歌词缓存是否存在失败 songId=$songId', e, s);
      return false;
    }
  }

  Future<String?> loadCachedLrc(String songId) async {
    return _readFromCache(songId);
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
      final file = File(p.join(lyricsDir.path, '${fnv1a64Hex(songId)}.lrc'));
      await file.writeAsString(content, flush: true);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '写入歌词缓存失败 songId=$songId', e, s);
    }
  }

  Future<File> _cacheFileForSongId(String songId) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'lyrics', '${fnv1a64Hex(songId)}.lrc'));
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
      final dirHandle = Directory(dir);
      if (!await dirHandle.exists()) return null;
      final entries = <File>[];
      // Async listing so a large lyrics folder never blocks the UI isolate.
      await for (final entry in dirHandle.list(followLinks: false)) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.lrc') {
          entries.add(entry);
        }
      }
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
