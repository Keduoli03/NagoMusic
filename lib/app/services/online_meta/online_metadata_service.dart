/// 在线元数据补全：拿 QQ 音乐的搜索结果，把歌名 / 歌手 / 专辑 / 封面 / 歌词
/// 写回本地歌曲。
library;

import '../../state/song_state.dart';
import '../artwork_cache_helper.dart';
import '../db/dao/song_dao.dart';
import '../log/log.dart';
import '../lyrics/lyrics_repository.dart';
import 'vkeys_music_api.dart';

/// 一次匹配要覆盖哪些字段。默认三项全开。
class OnlineMatchOptions {
  final bool applyInfo;
  final bool applyCover;
  final bool applyLyrics;

  /// 歌词是否连翻译一起存。
  final bool includeTranslation;

  const OnlineMatchOptions({
    this.applyInfo = true,
    this.applyCover = true,
    this.applyLyrics = true,
    this.includeTranslation = true,
  });

  bool get isNoop => !applyInfo && !applyCover && !applyLyrics;

  OnlineMatchOptions copyWith({
    bool? applyInfo,
    bool? applyCover,
    bool? applyLyrics,
    bool? includeTranslation,
  }) {
    return OnlineMatchOptions(
      applyInfo: applyInfo ?? this.applyInfo,
      applyCover: applyCover ?? this.applyCover,
      applyLyrics: applyLyrics ?? this.applyLyrics,
      includeTranslation: includeTranslation ?? this.includeTranslation,
    );
  }
}

/// 应用一次匹配之后，各项到底成没成。UI 拿它拼提示文案。
class OnlineMatchOutcome {
  final SongEntity song;
  final bool infoApplied;
  final bool coverApplied;
  final bool lyricsApplied;

  const OnlineMatchOutcome({
    required this.song,
    required this.infoApplied,
    required this.coverApplied,
    required this.lyricsApplied,
  });

  bool get anythingApplied => infoApplied || coverApplied || lyricsApplied;
}

class OnlineMetadataService {
  static const String _logTag = 'OnlineMetadataService';

  OnlineMetadataService._();

  static final OnlineMetadataService instance = OnlineMetadataService._();

  final VkeysMusicApi _api = VkeysMusicApi.instance;
  final SongDao _songDao = SongDao();
  final LyricsRepository _lyrics = LyricsRepository();

  /// 本进程内 songId → 自动匹配结果的备忘（null 表示匹配过但没匹配上）。
  ///
  /// 播一首歌时歌词和封面是两条独立的补全路径，都会走 [autoMatch]。没有这层
  /// 备忘的话同一首歌会白发两遍搜索请求。只在内存里，重启后重新匹配。
  final Map<String, VkeysSong?> _matchCache = {};

  /// 忘掉 [songId] 的匹配结果，下次重新联网找。
  void invalidateMatch(String songId) => _matchCache.remove(songId);

  /// 搜索关键词。结果里的同名多版本（`grp`）会被摊平到同一层，因为用户要挑的是
  /// "哪一版"，把它藏在二级列表里等于逼人多点一次。
  Future<List<VkeysSong>> search(String keyword, {int page = 1}) async {
    final results = await _api.search(keyword, page: page);
    final flattened = <VkeysSong>[];
    final seen = <String>{};
    for (final item in results) {
      for (final candidate in [item, ...item.variants]) {
        final key = candidate.mid.isNotEmpty
            ? candidate.mid
            : '${candidate.id}';
        if (!seen.add(key)) continue;
        flattened.add(candidate);
      }
    }
    return flattened;
  }

  /// 由一首本地歌曲推出默认搜索词。
  ///
  /// 只有当歌名看着**像个正经歌名**时才带上歌手：扫描出来的曲目常常拿文件名当
  /// 标题（`0038-爱情好无奈-六哲`），这种串里歌手名往往已经在里面了，再拼一次
  /// 只会让搜索命中率更差。
  String buildQuery(SongEntity song) {
    final title = _cleanTitle(song.title);
    final artist = song.artist.trim();
    if (title.isEmpty) return artist;
    if (artist.isEmpty || _isPlaceholderArtist(artist)) return title;
    if (title.toLowerCase().contains(artist.toLowerCase())) return title;
    return '$title $artist';
  }

  /// 自动挑一条最像的结果；没有足够像的就返回 null，交给用户手动搜。
  ///
  /// 宁可返回 null 也不要硬塞一个 —— 自动匹配错了会把好好的标签和封面覆盖掉，
  /// 比"没匹配上"糟糕得多。
  Future<VkeysSong?> autoMatch(SongEntity song) async {
    if (_matchCache.containsKey(song.id)) return _matchCache[song.id];
    final query = buildQuery(song);
    if (query.trim().isEmpty) return null;
    final results = await search(query);
    final best = pickBest(results, song);
    _matchCache[song.id] = best;
    return best;
  }

  /// 从**已有**结果里挑最像 [song] 的一条。
  ///
  /// 和 [autoMatch] 分开是为了让界面能复用刚搜出来的那批结果，点"自动选最佳"
  /// 不必再联网搜一次。
  VkeysSong? pickBest(List<VkeysSong> results, SongEntity song) {
    if (results.isEmpty) return null;

    final title = _cleanTitle(song.title).toLowerCase();
    final artist = song.artist.trim().toLowerCase();

    VkeysSong? best;
    var bestScore = 0.0;
    for (final candidate in results) {
      final score = _score(candidate, title: title, artist: artist);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    // 0.6：歌名基本吻合，或者歌名一般般但歌手对得上。低于这个宁可不认。
    return bestScore >= 0.6 ? best : null;
  }

  double _score(
    VkeysSong candidate, {
    required String title,
    required String artist,
  }) {
    final candTitle = candidate.song.trim().toLowerCase();
    final candArtist = candidate.singer.trim().toLowerCase();
    if (candTitle.isEmpty) return 0;

    var score = 0.0;
    if (title.isNotEmpty) {
      if (candTitle == title) {
        score += 0.7;
      } else if (title.contains(candTitle) || candTitle.contains(title)) {
        // 文件名式标题（`0038-爱情好无奈-六哲`）包含真正的歌名，算部分命中。
        score += 0.45;
      }
    }
    if (artist.isNotEmpty && candArtist.isNotEmpty) {
      if (candArtist == artist) {
        score += 0.3;
      } else if (artist.contains(candArtist) || candArtist.contains(artist)) {
        score += 0.2;
      }
    }
    // 标题里直接带着歌手名的情况（扫描出来的文件名标题最常见）。
    if (candArtist.isNotEmpty && title.contains(candArtist)) score += 0.15;
    return score;
  }

  /// 把 [match] 的内容写进 [song]，返回更新后的歌曲和各项结果。
  ///
  /// 歌词用 `overwrite: true` 存 —— 这是用户**主动**选的一条匹配，意图明确，
  /// 不该被"已经有缓存了"挡回去（那是自动兜底才需要的保护）。
  Future<OnlineMatchOutcome> apply({
    required SongEntity song,
    required VkeysSong match,
    OnlineMatchOptions options = const OnlineMatchOptions(),
  }) async {
    var coverPath = song.localCoverPath;
    var coverApplied = false;
    var lyricsApplied = false;

    if (options.applyCover && match.cover.isNotEmpty) {
      final bytes = await _api.fetchCover(match.cover);
      if (bytes != null && bytes.isNotEmpty) {
        final previous = (song.localCoverPath ?? '').trim();
        // replaceExisting: 这是用户主动换封面，新图要写成**另一个文件名**，
        // 否则路径不变，播放页会认为封面没变、一直显示旧图（见
        // ArtworkCacheHelper.cacheCompressedArtwork 的注释）。
        final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
          bytes: bytes,
          key: song.id,
          replaceExisting: true,
        );
        if (cached != null && cached.isNotEmpty && cached != previous) {
          // 旧图按路径删 —— 按 key 删是删不掉的，新旧文件名本来就不一样。
          if (previous.isNotEmpty) {
            await ArtworkCacheHelper.removeCachedArtworkByPath(previous);
          }
          coverPath = cached;
          coverApplied = true;
        }
      }
    }

    if (options.applyLyrics) {
      lyricsApplied = await _fetchAndStoreLyrics(
        songId: song.id,
        match: match,
        includeTranslation: options.includeTranslation,
      );
    }

    final infoApplied = options.applyInfo && match.song.trim().isNotEmpty;
    final updated = SongEntity(
      id: song.id,
      title: infoApplied ? match.song.trim() : song.title,
      artist: infoApplied && match.singer.trim().isNotEmpty
          ? match.singer.trim()
          : song.artist,
      album: infoApplied && match.album.trim().isNotEmpty
          ? match.album.trim()
          : song.album,
      uri: song.uri,
      isLocal: song.isLocal,
      headersJson: song.headersJson,
      durationMs: song.durationMs,
      bitrate: song.bitrate,
      sampleRate: song.sampleRate,
      fileSize: song.fileSize,
      format: song.format,
      sourceId: song.sourceId,
      fileModifiedMs: song.fileModifiedMs,
      localCoverPath: coverPath,
      localAssetId: song.localAssetId,
      tagsParsed: song.tagsParsed || infoApplied,
      trackNumber: song.trackNumber,
      discNumber: song.discNumber,
    );

    if (infoApplied || coverApplied) {
      await _songDao.upsertSongs([updated]);
    }

    AppLog.instance.i(
      _logTag,
      '在线匹配 songId=${song.id} -> ${match.song}/${match.singer} '
      'info=$infoApplied cover=$coverApplied lyrics=$lyricsApplied',
    );

    return OnlineMatchOutcome(
      song: updated,
      infoApplied: infoApplied,
      coverApplied: coverApplied,
      lyricsApplied: lyricsApplied,
    );
  }

  /// 只取封面并存进封面缓存，返回缓存路径；取不到返回 null。
  ///
  /// **不写数据库** —— 调用方是 `SongMetadataPersister`，它有自己的一套回写 +
  /// 刷新队列/currentSong 的流程，在这里再写一遍只会打架。
  ///
  /// 只在歌曲本来就没有封面时才应该调用：这里不会覆盖已有封面。
  Future<String?> fetchCoverOnly(SongEntity song) async {
    final match = await autoMatch(song);
    if (match == null || match.cover.trim().isEmpty) return null;
    final bytes = await _api.fetchCover(match.cover);
    if (bytes == null || bytes.isEmpty) return null;
    return ArtworkCacheHelper.cacheCompressedArtwork(
      bytes: bytes,
      key: song.id,
    );
  }

  /// 只取歌词，不碰标签和封面。
  ///
  /// 播放时的自动兜底走这条：先按歌名自动匹配，匹配得上就把歌词落盘。刻意**不**
  /// 顺手改标题/歌手/封面 —— 那是每播一首就悄悄改一次库，匹配错一次用户就得手动
  /// 还原，代价和收益完全不对等。要改这些请从「在线匹配」面板里明确选。
  ///
  /// 返回 true 表示确实存下了歌词。
  Future<bool> fetchLyricsOnly({
    required SongEntity song,
    bool includeTranslation = true,
  }) async {
    final match = await autoMatch(song);
    if (match == null) return false;
    return _fetchAndStoreLyrics(
      songId: song.id,
      match: match,
      includeTranslation: includeTranslation,
    );
  }

  /// 取歌词并落盘，普通 LRC 和逐字歌词各存一份。
  ///
  /// 两份分开存是因为 yrc 不带翻译：逐字时间从 yrc 来，翻译从 lrc 来，播放时再
  /// 按时间戳拼到一起（见 `LyricsParser.buildModelFromYrc`）。
  Future<bool> _fetchAndStoreLyrics({
    required String songId,
    required VkeysSong match,
    required bool includeTranslation,
  }) async {
    final lyrics = await _api.fetchLyrics(id: match.id, mid: match.mid);
    if (lyrics == null) return false;

    final text = lyrics.toLrc(includeTranslation: includeTranslation);
    if (text.trim().isEmpty) return false;

    await _lyrics.saveLrcToCache(songId, text, overwrite: true);
    if (lyrics.yrc.trim().isNotEmpty) {
      await _lyrics.saveYrcToCache(songId, lyrics.yrc);
    } else {
      // 这次的匹配没有逐字词，把上一次匹配留下的清掉，免得新歌词配旧逐字时间。
      await _lyrics.removeCachedYrc(songId);
    }
    return true;
  }

  static bool _isPlaceholderArtist(String artist) {
    const placeholders = {'未知艺术家', '未知歌手', '云端', 'unknown', '<unknown>'};
    return placeholders.contains(artist.trim().toLowerCase()) ||
        placeholders.contains(artist.trim());
  }

  /// 去掉文件名式标题里的噪声：前导曲目号、扩展名、方括号标记。
  ///
  /// 扫描出来的标题常常直接是文件名（`0038-爱情好无奈-六哲`、
  /// `[无损]告白气球`），原样拿去搜基本搜不到。
  static String _cleanTitle(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return t;
    // 扩展名
    t = t.replaceFirst(
      RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac|opus)$', caseSensitive: false),
      '',
    );
    // 方括号 / 圆括号里的标记：[无损]、【HQ】、(Live) 之类
    t = t.replaceAll(RegExp(r'[\[【(（][^\]】)）]{0,12}[\]】)）]'), ' ');
    // 前导曲目号：`0038-`、`03.`、`12 - `
    t = t.replaceFirst(RegExp(r'^\s*\d{1,4}\s*[-.、_]\s*'), '');
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
