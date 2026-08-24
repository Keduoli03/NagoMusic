import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../state/song_state.dart';
import '../db/dao/song_dao.dart';
import '../stats_service.dart';
import 'bili_api.dart';
import 'bili_audio_selector.dart';
import 'bili_models.dart';

/// 把 B 站视频接到本地曲库上。
///
/// 设计上有两条硬约束：
/// 1. **歌曲 id 里不能出现播放地址。** playurl 拿到的链接带时效签名，几十分钟就失效；
///    id 是收藏 / 歌单 / 播放统计的主键，必须永久稳定，所以用 `bili::<bvid>-<cid>`。
/// 2. **`uri` 只是缓存值。** 播放时由 [PlayerService] 回调 [resolveStreamUri] 重新拿
///    新链接，DB 里那条过期 URL 只用来避免冷启动多一次请求。
class BiliMusicService {
  static final BiliMusicService instance = BiliMusicService._();

  BiliMusicService._();

  /// 所有 B 站曲目共用这一个 sourceId —— 它不是用户添加的音源，而是登录制的内置源。
  static const String sourceId = 'bili';
  static const String _idPrefix = '$sourceId::';

  /// B 站封面缓存目录名。暴露出来是为了让 `storage_sections.dart` 里的
  /// 「存储与缓存」页统计能跟 [_coverDir] 用同一个字符串，不会因为改名漂移。
  static const String coverDirName = 'bili_covers';

  final BiliApi _api = BiliApi.instance;
  final SongDao _songDao = SongDao();
  final Dio _dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  static bool isBiliSong(SongEntity song) =>
      song.sourceId == sourceId || song.id.startsWith(_idPrefix);

  static String buildSongId(String bvid, int cid) => '$_idPrefix$bvid-$cid';

  /// 曲目 `uri` 里存的占位地址，例如 `bili://BV1xx411c7mD/123456`。
  ///
  /// 不能把真的直链存进去：它带时效签名，几十分钟就失效。但 `uri` 又不能为空 ——
  /// [PlayerService.playQueue] 会把 `uri` 为空的歌全部滤掉，队列直接变空、点了没反应。
  /// 占位地址同时充当音频缓存的键，它稳定，所以缓存不会因为换了直链就失效。
  static String placeholderUri(String songId) {
    final parsed = parseSongId(songId);
    if (parsed == null) return 'bili://$songId';
    return 'bili://${parsed.$1}/${parsed.$2}';
  }

  /// `bili::BV1xx411c7mD-123456` → `('BV1xx411c7mD', 123456)`。
  /// 解不出来返回 null（例如 id 格式被别的迁移改过）。
  static (String, int)? parseSongId(String id) {
    if (!id.startsWith(_idPrefix)) return null;
    final body = id.substring(_idPrefix.length);
    final dash = body.lastIndexOf('-');
    if (dash <= 0) return null;
    final bvid = body.substring(0, dash);
    final cid = int.tryParse(body.substring(dash + 1));
    if (bvid.isEmpty || cid == null) return null;
    return (bvid, cid);
  }

  // ------------------------------------------------------------ 视频 → 曲目

  /// 把一个视频展开成曲目列表：多 P 视频每个分 P 一首，单 P 就是一首。
  ///
  /// 这一步**不**请求 playurl（那是每个分 P 一次请求，一个 100P 的合集会打爆接口），
  /// `uri` 留空，等真正播放时再解析。
  Future<List<SongEntity>> songsFromVideo(String bvid) async {
    final detail = await _api.videoDetail(bvid);
    return songsFromDetail(detail);
  }

  /// 分 P 的显示名。
  ///
  /// 很多合集（有声书、课程）每个分 P 的 `part` 字段就是视频标题本身，直接拿来用
  /// 会得到一整列一模一样的长标题 —— 这种情况退回 `P1 / P2`。
  static String partLabel(String videoTitle, BiliPart part) {
    final raw = part.title.trim();
    if (raw.isEmpty || raw == videoTitle.trim()) return 'P${part.index}';
    return raw;
  }

  List<SongEntity> songsFromDetail(BiliVideoDetail detail) {
    final video = detail.video;
    final parts = detail.parts;
    if (parts.isEmpty) return const [];
    final multiPart = parts.length > 1;
    return parts.map((part) {
      final label = partLabel(video.title, part);
      // 分 P 名本身就是曲名（「01 三体I-科学边界」），前面再拼一遍视频标题的话，
      // 列表里一行放不下，真正有区分度的分 P 名反而被挤出可视区。视频标题放
      // album，专辑分组和详情页都还看得到。
      //
      // 唯一的例外是 partLabel 回退成 "P3" 的情况 —— 光一个 "P3" 认不出是哪个
      // 视频的，这时才补上视频标题。
      final title = !multiPart
          ? video.title
          : (label == 'P${part.index}' ? '${video.title} · $label' : label);
      final id = buildSongId(video.bvid, part.cid);
      return SongEntity(
        id: id,
        title: title,
        artist: video.author.isEmpty ? '哔哩哔哩' : video.author,
        album: multiPart ? video.title : null,
        uri: placeholderUri(id),
        isLocal: false,
        durationMs:
            (part.durationSec > 0 ? part.durationSec : video.durationSec) *
            1000,
        format: 'M4A',
        sourceId: sourceId,
        // 封面异步补，见 [cacheCover]。
        localCoverPath: null,
        tagsParsed: true,
        trackNumber: multiPart ? part.index : null,
      );
    }).toList();
  }

  /// 收藏夹条目 → 曲目。多 P 的走 [songsFromVideo] 展开，单 P 的直接合成，
  /// 省掉一次 view 请求（收藏夹接口已经给了标题 / UP / 时长）。
  Future<List<SongEntity>> songsFromFavVideo(BiliVideo video) async {
    if (video.partCount > 1) {
      try {
        return await songsFromVideo(video.bvid);
      } catch (_) {
        // 分 P 拉失败就退化成「整个视频当一首」，总比整条丢掉强。
      }
    }
    final detail = await _api.videoDetail(video.bvid);
    return songsFromDetail(detail);
  }

  // ------------------------------------------------------------- 落库 / 封面

  /// 写进 songs 表。只有真正被播放 / 被收藏的曲目才落库，搜索结果不落。
  Future<void> persist(List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    await _songDao.upsertSongs(songs);
  }

  /// 最近播放过的 B 站曲目，最近的在前。
  ///
  /// `song_stats` 表里没有 sourceId 列，没法在 SQL 层过滤，只能多取一些再按
  /// id 前缀在 Dart 侧筛。[scanLimit] 是往前翻多少条播放记录去找。
  Future<List<SongEntity>> recentlyPlayed({
    int limit = 12,
    int scanLimit = 300,
  }) async {
    final stats = await StatsService.instance.fetchRecentSongs(
      limit: scanLimit,
    );
    final ids = stats
        .map((e) => e.songId)
        .where((id) => id.startsWith(_idPrefix))
        .take(limit)
        .toList();
    if (ids.isEmpty) return const [];
    final songs = await _songDao.fetchByIds(ids);
    // fetchByIds 不保证顺序，按「最近播放」的原顺序重排。
    final byId = {for (final song in songs) song.id: song};
    return [for (final id in ids) ?byId[id]];
  }

  /// 下载封面到本地并回填 `localCoverPath`。失败就返回原对象，不影响播放。
  Future<SongEntity> cacheCover(SongEntity song, String coverUrl) async {
    if (coverUrl.isEmpty) return song;
    final parsed = parseSongId(song.id);
    if (parsed == null) return song;
    try {
      final dir = await _coverDir();
      final file = File(p.join(dir.path, '${parsed.$1}.jpg'));
      if (!await file.exists()) {
        final response = await _dio.get<List<int>>(
          coverUrl,
          options: Options(
            headers: {
              'User-Agent': BiliApi.userAgent,
              'Referer': BiliApi.referer,
            },
          ),
        );
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) return song;
        await file.writeAsBytes(bytes, flush: true);
      }
      return song.copyWith(localCoverPath: file.path);
    } catch (_) {
      return song;
    }
  }

  Future<Directory> _coverDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, coverDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ------------------------------------------------------------ 播放地址解析

  /// 解析出一条**当前有效**的音频直链。
  ///
  /// 结果按 [_urlTtl] 缓存在内存里：一次播放里 warmup、正式播放、下一首预取
  /// 会连着问三遍，没缓存就是三次 playurl 请求。
  static const Duration _urlTtl = Duration(minutes: 25);
  final Map<String, _ResolvedStream> _streamCache = {};
  final Map<String, Future<String?>> _inflight = {};

  Future<String?> resolveStreamUri(
    String songId, {
    bool forceRefresh = false,
  }) async {
    final parsed = parseSongId(songId);
    if (parsed == null) return null;

    if (forceRefresh) {
      _streamCache.remove(songId);
      _inflight.remove(songId);
    } else {
      final cached = _streamCache[songId];
      if (cached != null && !cached.isExpired) return cached.url;
    }

    final inflight = _inflight[songId];
    if (inflight != null) return inflight;

    final future = () async {
      final streams = await _api.audioStreams(bvid: parsed.$1, cid: parsed.$2);
      final best = BiliAudioSelector.best(streams);
      if (best == null) return null;
      _streamCache[songId] = _ResolvedStream(best.url, DateTime.now());
      // 顺手把码率 / 格式补进 DB，歌曲详情页才能显示音质。
      unawaited(_updateQuality(songId, best));
      return best.url;
    }();

    _inflight[songId] = future;
    future.whenComplete(() => _inflight.remove(songId));
    return future;
  }

  Future<void> _updateQuality(String songId, BiliAudioStream stream) async {
    try {
      final rows = await _songDao.fetchByIds([songId]);
      if (rows.isEmpty) return;
      final song = rows.first;
      if (song.bitrate == stream.bandwidth) return;
      await _songDao.upsertSongs([
        song.copyWith(
          bitrate: stream.bandwidth,
          format: stream.id == 30251 ? 'FLAC' : 'M4A',
        ),
      ]);
    } catch (_) {
      // 音质标签是锦上添花，写失败不该影响播放。
    }
  }

  /// 播放时要带的请求头（Referer 缺了 CDN 直接 403）。
  Future<Map<String, String>> headersMap() => _api.streamHeaders();

  Future<String> headersJson() async {
    return jsonEncode(await headersMap());
  }

  void invalidate(String songId) {
    _streamCache.remove(songId);
    _inflight.remove(songId);
  }
}

class _ResolvedStream {
  final String url;
  final DateTime at;

  const _ResolvedStream(this.url, this.at);

  bool get isExpired =>
      DateTime.now().difference(at) > BiliMusicService._urlTtl;
}
