import 'dart:async';
import 'dart:typed_data';

import 'package:media_cache/media_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/song_state.dart';
import '../artwork_cache_helper.dart';
import '../db/dao/song_dao.dart';
import '../log/log.dart';
import '../lyrics/lyrics_repository.dart';
import '../online_meta/online_metadata_service.dart';

/// 曲目元数据的后台探测与回写，从 [PlayerService] 里抽出来。
///
/// 负责「这首歌还缺封面/时长/歌词/标签 → 去刮削 → 写回 DB → 通知持有者更新
/// 内存里的队列和 currentSong」。**完全不碰 AudioPlayer 和队列状态本身** ——
/// 队列 / currentSong / 快照都归持有者所有，这里通过 [onSongPersisted] 回调
/// 把更新后的 [SongEntity] 交出去。
class SongMetadataPersister {
  static const String _logTag = 'SongMetadataPersister';

  /// 文件里没有内嵌封面时，去 QQ 音乐按歌名找一张。默认开。
  static const String prefsOnlineCoverEnabled = 'online_meta_cover_enabled';

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

  /// 这一轮已经联网找过封面、但没找到的歌曲。避免每次回写都重发一遍搜索。
  final Set<String> _onlineCoverMisses = <String>{};

  /// 正在联网找封面的歌曲，防止同一首歌被并发触发多次。
  final Set<String> _onlineCoverInflight = <String>{};

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

    // 在线封面**不等**标签探测，单独一条路并行跑。
    //
    // 下面那套内嵌标签探测要先解析 WebDAV 地址、再下载音频文件的字节区间才能读到
    // 标签（WAV 的 ID3 块通常在文件尾，还得多拉一次 range）—— 远端大文件动辄好几
    // 秒甚至更久。而在线封面只是一次搜索加一张几十 KB 的图，串在后面等纯属浪费。
    //
    // 两条路最终都写同一个缓存键（song.id），`cacheCompressedArtwork` 命中已存在
    // 的文件会直接返回原路径，所以谁先到都不会互相覆盖或写坏。
    if (!hasCover) {
      unawaited(_startOnlineCoverFetch(song));
    }

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

  /// 独立于标签探测的在线封面补全：拿到就立刻回写，不等别的。
  ///
  /// `maybeProbe` 会被多处调用（切歌、索引变化、2 秒后的 deferred probe），
  /// 用 [_onlineCoverInflight] 保证同一首歌只发一轮请求。
  Future<void> _startOnlineCoverFetch(SongEntity song) async {
    if (!_onlineCoverInflight.add(song.id)) return;
    try {
      final coverPath = await _fetchOnlineCover(song);
      if (coverPath == null || coverPath.isEmpty) return;
      // 等回来的这段时间里内嵌标签可能已经补上封面了，那就不用再写一遍。
      if (!isCurrentSong(song.id)) return;
      await _persistSongUpdate(song, localCoverPath: coverPath);
    } finally {
      _onlineCoverInflight.remove(song.id);
    }
  }

  /// 决定这首歌最终用哪张封面：已有的 > 文件内嵌的。
  ///
  /// 线上那条路不在这里 —— 它由 [_startOnlineCoverFetch] 并行跑，不能让它跟在
  /// 标签探测后面串行等待。
  Future<String?> _resolveCover(SongEntity song, Uint8List? artwork) async {
    final existing = (song.localCoverPath ?? '').trim();
    if (existing.isNotEmpty) return song.localCoverPath;

    if (artwork != null && artwork.isNotEmpty) {
      final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
        bytes: artwork,
        key: song.id,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    return null;
  }

  Future<String?> _fetchOnlineCover(SongEntity song) async {
    if (_onlineCoverMisses.contains(song.id)) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(prefsOnlineCoverEnabled) ?? true)) return null;

      final path = await OnlineMetadataService.instance.fetchCoverOnly(song);
      if (path == null || path.isEmpty) {
        _onlineCoverMisses.add(song.id);
        return null;
      }
      return path;
    } catch (e, s) {
      // 网络不通 / 没匹配上 —— 和「这首没封面」是同一个结果，不该打断播放。
      AppLog.instance.w(_logTag, '在线封面获取失败 song=${song.title}', e, s);
      _onlineCoverMisses.add(song.id);
      return null;
    }
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
    if (result == null) {
      // 封面已经由 _startOnlineCoverFetch 并行在找了，这里没有别的可做。
      return;
    }

    final coverPath = await _resolveCover(song, result.artwork);

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
    if (result == null) {
      // 同上：封面由 _startOnlineCoverFetch 并行负责。
      return;
    }

    final coverPath = await _resolveCover(song, result.artwork);

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
