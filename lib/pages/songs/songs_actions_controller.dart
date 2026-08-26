import 'dart:convert';

import 'package:media_cache/media_cache.dart';

import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';

class SongsScrapeBatchResult {
  final int total;
  final int success;

  const SongsScrapeBatchResult({required this.total, required this.success});
}

class SongsActionsController {
  final SongDao _songDao;
  final LyricsRepository _lyricsRepo;
  final AudioCacheService _audioCache;
  final PlayerService _playerService;

  SongsActionsController({
    SongDao? songDao,
    LyricsRepository? lyricsRepository,
    AudioCacheService? audioCache,
    PlayerService? playerService,
  }) : _songDao = songDao ?? SongDao(),
       _lyricsRepo = lyricsRepository ?? LyricsRepository(),
       _audioCache = audioCache ?? AudioCacheService.instance,
       _playerService = playerService ?? PlayerService.instance;

  Future<bool> addSelectedToPlaylist({
    required Future<bool?> Function(List<String> songIds) openDialog,
    required Set<String> selectedIds,
  }) async {
    if (selectedIds.isEmpty) return false;
    final added = await openDialog(selectedIds.toList(growable: false));
    return added == true;
  }

  /// 批量移除歌曲。
  ///
  /// 分两段：先一次性把数据库和播放队列清干净并让列表立刻更新，再去逐首删各自
  /// 的缓存文件。
  ///
  /// 以前是每首歌走一整轮「删 DB → 出队列 → 删缓存 → 通知 UI」，删 200 首就是
  /// 200 次独立 DB 往返加 200 轮串行文件 I/O。而 [SongDao.deleteByIds] 本来就收
  /// 整个 id 列表（内部按 500 切批），播放队列那边同理。
  ///
  /// 缓存清理留在后面并且**保持逐首推进**，是因为它才是真正耗时的那部分（歌词
  /// 文件、封面文件、远端音频缓存、探测缓存），进度条报的就是它；而用户想看到的
  /// 「行消失」在第一段就已经发生了，不必等文件删完。
  Future<int> removeSongs({
    required List<SongEntity> songsToRemove,
    required Future<void> Function(int processed, int total) onProgress,
    required Future<void> Function(List<SongEntity> removedSongs)
    onSongsRemoved,
    required void Function(SongEntity song) clearArtwork,
  }) async {
    if (songsToRemove.isEmpty) return 0;
    final total = songsToRemove.length;
    final ids = songsToRemove.map((s) => s.id).toList(growable: false);

    final removedCount = await _songDao.deleteByIds(ids);
    await _playerService.removeSongsById(ids);
    await onSongsRemoved(songsToRemove);

    var processed = 0;
    for (final song in songsToRemove) {
      await _cleanupSongCaches(song, clearArtwork: clearArtwork);
      processed += 1;
      await onProgress(processed, total);
    }
    return removedCount;
  }

  Future<List<SongEntity>> collectSongsToScrape(
    List<SongEntity> candidates,
  ) async {
    final result = <SongEntity>[];
    for (final song in candidates) {
      final skip = await _shouldSkipTagProbe(song);
      if (!skip) {
        result.add(song);
      }
    }
    return result;
  }

  Future<SongsScrapeBatchResult> scrapeSongs({
    required List<SongEntity> songs,
    required Future<void> Function(int done, int success, int total) onProgress,
    required Future<void> Function(SongEntity updatedSong) onSongUpdated,
  }) async {
    if (songs.isEmpty) {
      return const SongsScrapeBatchResult(total: 0, success: 0);
    }

    var nextIndex = 0;
    var done = 0;
    var success = 0;
    final workerCount = songs.length < 4 ? songs.length : 4;

    Future<void> worker() async {
      while (true) {
        final idx = nextIndex;
        if (idx >= songs.length) return;
        nextIndex += 1;
        final song = songs[idx];
        SongEntity? updated;
        try {
          updated = await scrapeOneSong(song);
        } catch (_) {
          updated = null;
        }

        if (updated != null) {
          await _songDao.upsertSongs([updated]);
          await onSongUpdated(updated);
          success += 1;
        }
        done += 1;
        await onProgress(done, success, songs.length);
      }
    }

    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    return SongsScrapeBatchResult(total: songs.length, success: success);
  }

  Future<SongEntity?> scrapeOneSong(SongEntity song) async {
    final uri = (song.uri ?? '').trim();
    if (uri.isEmpty) return null;
    final headers = song.isLocal ? null : _headersFromSong(song);
    final result = song.isLocal
        ? await TagProbeService.instance.probeSong(
            uri: uri,
            isLocal: true,
            includeArtwork: true,
          )
        : await TagProbeService.instance.probeSongDedup(
            uri: uri,
            isLocal: false,
            headers: headers,
            includeArtwork: true,
          );
    if (result == null) return null;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if (artwork != null && artwork.isNotEmpty) {
      final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
        bytes: artwork,
        key: song.id,
      );
      if (cached != null && cached.isNotEmpty) {
        coverPath = cached;
      }
    }

    final lyrics = (result.lyrics ?? '').trim();
    if (lyrics.isNotEmpty) {
      await _lyricsRepo.saveLrcToCache(song.id, lyrics, overwrite: false);
    }

    final updated = SongEntity(
      id: song.id,
      title: (result.title ?? '').trim().isNotEmpty
          ? result.title!.trim()
          : song.title,
      artist: (result.artist ?? '').trim().isNotEmpty
          ? result.artist!.trim()
          : song.artist,
      album: (result.album ?? '').trim().isNotEmpty
          ? result.album!.trim()
          : song.album,
      uri: song.uri,
      isLocal: song.isLocal,
      headersJson: song.headersJson,
      durationMs: result.durationMs ?? song.durationMs,
      bitrate: result.bitrate ?? song.bitrate,
      sampleRate: result.sampleRate ?? song.sampleRate,
      fileSize: result.fileSize ?? song.fileSize,
      format: result.format ?? song.format,
      sourceId: song.sourceId,
      fileModifiedMs: song.fileModifiedMs,
      localCoverPath: coverPath,
      localAssetId: song.localAssetId,
      tagsParsed: true,
    );

    final hasChanges =
        updated.title != song.title ||
        updated.artist != song.artist ||
        updated.album != song.album ||
        updated.durationMs != song.durationMs ||
        updated.bitrate != song.bitrate ||
        updated.sampleRate != song.sampleRate ||
        updated.fileSize != song.fileSize ||
        updated.format != song.format ||
        updated.localCoverPath != song.localCoverPath ||
        updated.tagsParsed != song.tagsParsed;
    if (!hasChanges) return updated;
    return updated;
  }

  Map<String, String> _headersFromSong(SongEntity song) {
    final raw = (song.headersJson ?? '').trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return const {};
  }

  bool _isMeaningfulTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return false;
    const bad = {'未知标题', 'unknown', 'unknown title', 'untitled'};
    return !bad.contains(t.toLowerCase());
  }

  bool _isMeaningfulArtist(String artist) {
    final t = artist.trim();
    if (t.isEmpty) return false;
    const bad = {'未知艺术家', 'unknown', 'unknown artist'};
    return !bad.contains(t.toLowerCase());
  }

  Future<bool> _shouldSkipTagProbe(SongEntity song) async {
    final hasBasics =
        _isMeaningfulTitle(song.title) &&
        _isMeaningfulArtist(song.artist) &&
        (song.album ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasLyrics = await _lyricsRepo.hasCachedLrc(song.id);
    final hasExtras = hasCover || hasLyrics || hasDuration;
    return song.tagsParsed && hasBasics && hasExtras;
  }

  Future<void> _cleanupSongCaches(
    SongEntity song, {
    required void Function(SongEntity song) clearArtwork,
  }) async {
    clearArtwork(song);
    await _lyricsRepo.removeCachedLrc(song.id);

    final coverPath = (song.localCoverPath ?? '').trim();
    if (coverPath.isNotEmpty) {
      await ArtworkCacheHelper.removeCachedArtworkByPath(coverPath);
    }
    await ArtworkCacheHelper.removeCachedArtwork(key: song.id);

    final uri = (song.uri ?? '').trim();
    if (song.isLocal || uri.isEmpty || !uri.startsWith('http')) return;
    final headers = _headersFromSong(song);
    await _audioCache.removeCachedFiles(
      uri: uri,
      headers: headers.isEmpty ? null : headers,
    );
    await TagProbeService.instance.removeRemoteProbeCache(
      uri: uri,
      headers: headers.isEmpty ? null : headers,
    );
  }
}
