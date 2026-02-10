import 'dart:typed_data';

import '../core/cache/cache_manager.dart';
import '../core/database/database_helper.dart';
import '../models/music_entity.dart';
import 'tag_probe_service.dart';

class BatchTagProcessor {
  final TagProbeService _probe = TagProbeService();
  Future<List<MusicEntity>> process(List<MusicEntity> songs, {int concurrency = 4}) async {
    if (songs.isEmpty) return [];
    final results = List<MusicEntity?>.filled(songs.length, null);
    final db = DatabaseHelper();
    final cache = CacheManager();
    var nextIndex = 0;
    final workerCount =
        concurrency <= 0 ? 1 : (concurrency > songs.length ? songs.length : concurrency);

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex;
        if (idx >= songs.length) return;
        nextIndex++;
        final song = songs[idx];
        if (song.isLocal && song.tagsParsed) {
          results[idx] = song;
          continue;
        }
        final result = await _probe.probeSong(song);
        if (result == null) {
          results[idx] = song;
          continue;
        }
        final Uint8List? artworkBytes = result.artwork;
        final String? normalizedLyrics = result.lyrics;
        final String? newTitle = result.title;
        final String? newArtist = result.artist;
        final String? newAlbum = result.album;
        String? localCoverPath = song.localCoverPath;
        if (artworkBytes != null && artworkBytes.isNotEmpty) {
          final coverFile = await cache.saveCoverImage(song.id, artworkBytes);
          localCoverPath = coverFile?.path ?? localCoverPath;
        }
        final updated = song.copyWith(
          title: newTitle?.isNotEmpty == true ? newTitle : song.title,
          artist: newArtist?.isNotEmpty == true ? newArtist : song.artist,
          album: newAlbum?.isNotEmpty == true ? newAlbum : song.album,
          artwork: artworkBytes?.isNotEmpty == true ? artworkBytes : song.artwork,
          localCoverPath: localCoverPath,
          lyrics: normalizedLyrics ?? song.lyrics,
          tagsParsed: true,
        );
        await db.insertSong(updated);
        results[idx] = updated;
      }
    }

    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    return results.whereType<MusicEntity>().toList();
  }

  Future<List<MusicEntity>> processTextOnly(
    List<MusicEntity> songs, {
    int concurrency = 6,
  }) async {
    if (songs.isEmpty) return [];
    final results = List<MusicEntity?>.filled(songs.length, null);
    var nextIndex = 0;
    final workerCount =
        concurrency <= 0 ? 1 : (concurrency > songs.length ? songs.length : concurrency);

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex;
        if (idx >= songs.length) return;
        nextIndex++;
        final song = songs[idx];
        if (song.isLocal && song.tagsParsed) {
          results[idx] = song;
          continue;
        }
        final result = await _probe.probeSong(song);
        if (result == null) {
          results[idx] = song;
          continue;
        }
        final String? normalizedLyrics = result.lyrics;
        final String? newTitle = result.title;
        final String? newArtist = result.artist;
        final String? newAlbum = result.album;
        final updated = song.copyWith(
          title: newTitle?.isNotEmpty == true ? newTitle : song.title,
          artist: newArtist?.isNotEmpty == true ? newArtist : song.artist,
          album: newAlbum?.isNotEmpty == true ? newAlbum : song.album,
          lyrics: normalizedLyrics ?? song.lyrics,
          fileModifiedMs: song.fileModifiedMs,
        );
        results[idx] = updated;
      }
    }

    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    return results.whereType<MusicEntity>().toList();
  }
}
