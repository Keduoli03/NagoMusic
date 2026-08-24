import 'dart:async';

import 'package:media_cache/media_cache.dart';

import '../../state/song_state.dart';
import '../artwork_cache_helper.dart';
import '../db/dao/song_dao.dart';
import '../lyrics/lyrics_repository.dart';

/// 曲目元数据的后台探测与回写，从 [PlayerService] 里抽出来。
///
/// 负责「这首歌还缺封面/时长/歌词/标签 → 去刮削 → 写回 DB → 通知持有者更新
/// 内存里的队列和 currentSong」。**完全不碰 AudioPlayer 和队列状态本身** ——
/// 队列 / currentSong / 快照都归持有者所有，这里通过 [onSongPersisted] 回调
/// 把更新后的 [SongEntity] 交出去。
class SongMetadataPersister {
  final SongDao _songDao;
  final LyricsRepository _lyricsRepo;

  /// 远端曲目的直链解析（WebDAV 多地址重写）。源解析器还没抽出来前，
  /// 由 PlayerService 绑定自己的 `_resolveWebdavRawUri`。
  final Future<String> Function(SongEntity song, String rawUri) resolveRawUri;

  /// 远端曲目的请求头。同样由 PlayerService 绑定。
  final Map<String, String>? Function(SongEntity song) headersFor;

  /// 曲目更新（写回 DB 之后）的联动：写回队列、刷新 currentSong、预热下一首、
  /// 发快照。持有者才是这些状态的所有者。
  final void Function(SongEntity next) onSongPersisted;

  /// 某首歌是否仍是当前播放项。deferred probe 在 2 秒后还要确认没切歌。
  final bool Function(String songId) isCurrentSong;

  final Map<String, Future<void>> _probeInflight = {};
  final Map<String, int> _durationPersistedMs = {};

  SongMetadataPersister({
    SongDao? songDao,
    LyricsRepository? lyricsRepo,
    required this.resolveRawUri,
    required this.headersFor,
    required this.onSongPersisted,
    required this.isCurrentSong,
  }) : _songDao = songDao ?? SongDao(),
       _lyricsRepo = lyricsRepo ?? LyricsRepository();

  void maybeProbe(SongEntity song) {
    unawaited(_maybeProbeAsync(song));
  }

  void scheduleDeferredProbe(SongEntity song) {
    unawaited(_deferredProbe(song));
  }

  Future<void> _maybeProbeAsync(SongEntity song) async {
    final hasCover = (song.localCoverPath ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasLyrics = await _lyricsRepo.hasCachedLrc(song.id);
    final uri = (song.uri ?? '').trim();
    final shouldProbe =
        !song.tagsParsed || !hasCover || !hasDuration || !hasLyrics;
    if (!shouldProbe) return;

    if (song.isLocal) {
      if (uri.isEmpty) return;
      final key =
          'local:${song.id}:${hasCover ? 1 : 0}:${hasDuration ? 1 : 0}:${song.tagsParsed ? 1 : 0}';
      if (_probeInflight.containsKey(key)) return;
      final future = _probeLocalAndPersist(song, uri: uri);
      _probeInflight[key] = future;
      future.whenComplete(() => _probeInflight.remove(key));
      return;
    }

    if (!uri.startsWith('http')) return;

    final resolvedUri = await resolveRawUri(song, uri);
    final headers = headersFor(song);
    final key =
        '${song.id}:${hasCover ? 1 : 0}:${hasDuration ? 1 : 0}:${song.tagsParsed ? 1 : 0}';
    if (_probeInflight.containsKey(key)) return;

    final future = _probeAndPersist(song, uri: resolvedUri, headers: headers);
    _probeInflight[key] = future;
    future.whenComplete(() => _probeInflight.remove(key));
  }

  Future<void> _deferredProbe(SongEntity song) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!isCurrentSong(song.id)) return;
    maybeProbe(song);
  }

  void persistPlaybackDuration(SongEntity song, int durationMs) {
    final existing = song.durationMs ?? 0;
    if (existing > 0) return;
    final prev = _durationPersistedMs[song.id] ?? 0;
    if (prev == durationMs) return;
    _durationPersistedMs[song.id] = durationMs;
    _persistSongUpdate(song, durationMs: durationMs);
  }

  Future<void> _persistSongUpdate(
    SongEntity song, {
    int? durationMs,
    String? localCoverPath,
    String? title,
    String? artist,
    String? album,
    int? bitrate,
    int? sampleRate,
    int? fileSize,
    String? format,
    bool? tagsParsed,
  }) async {
    final next = SongEntity(
      id: song.id,
      title: title ?? song.title,
      artist: artist ?? song.artist,
      album: album ?? song.album,
      uri: song.uri,
      isLocal: song.isLocal,
      headersJson: song.headersJson,
      durationMs: durationMs ?? song.durationMs,
      bitrate: bitrate ?? song.bitrate,
      sampleRate: sampleRate ?? song.sampleRate,
      fileSize: fileSize ?? song.fileSize,
      format: format ?? song.format,
      sourceId: song.sourceId,
      fileModifiedMs: song.fileModifiedMs,
      localCoverPath: localCoverPath ?? song.localCoverPath,
      localAssetId: song.localAssetId,
      tagsParsed: tagsParsed ?? song.tagsParsed,
    );

    await _songDao.upsertSongs([next]);
    onSongPersisted(next);
  }

  Future<void> _probeAndPersist(
    SongEntity song, {
    required String uri,
    Map<String, String>? headers,
  }) async {
    final result = await TagProbeService.instance.probeSongDedup(
      uri: uri,
      isLocal: false,
      headers: headers,
      includeArtwork: true,
    );
    if (result == null) return;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if ((coverPath ?? '').trim().isEmpty &&
        artwork != null &&
        artwork.isNotEmpty) {
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

    final title = (result.title ?? '').trim().isNotEmpty
        ? result.title!.trim()
        : null;
    final artist = (result.artist ?? '').trim().isNotEmpty
        ? result.artist!.trim()
        : null;
    final album = (result.album ?? '').trim().isNotEmpty
        ? result.album!.trim()
        : null;
    await _persistSongUpdate(
      song,
      title: title,
      artist: artist,
      album: album,
      durationMs: result.durationMs,
      bitrate: result.bitrate,
      sampleRate: result.sampleRate,
      fileSize: result.fileSize,
      format: result.format,
      localCoverPath: coverPath,
      tagsParsed: true,
    );
  }

  Future<void> _probeLocalAndPersist(
    SongEntity song, {
    required String uri,
  }) async {
    final result = await TagProbeService.instance.probeSongDedup(
      uri: uri,
      isLocal: true,
      includeArtwork: true,
    );
    if (result == null) return;

    String? coverPath = song.localCoverPath;
    final artwork = result.artwork;
    if ((coverPath ?? '').trim().isEmpty &&
        artwork != null &&
        artwork.isNotEmpty) {
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

    final title = (result.title ?? '').trim().isNotEmpty
        ? result.title!.trim()
        : null;
    final artist = (result.artist ?? '').trim().isNotEmpty
        ? result.artist!.trim()
        : null;
    final album = (result.album ?? '').trim().isNotEmpty
        ? result.album!.trim()
        : null;
    await _persistSongUpdate(
      song,
      title: title,
      artist: artist,
      album: album,
      durationMs: result.durationMs,
      bitrate: result.bitrate,
      sampleRate: result.sampleRate,
      fileSize: result.fileSize,
      format: result.format,
      localCoverPath: coverPath,
      tagsParsed: true,
    );
  }
}
