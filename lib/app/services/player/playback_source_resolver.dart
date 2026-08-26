import 'dart:async';
import 'dart:convert';

import 'package:just_audio/just_audio.dart';
import 'package:media_cache/media_cache.dart';

import '../../state/song_state.dart';
import '../bili/bili_music_service.dart';
import '../log/log.dart';
import '../webdav/webdav_endpoint_resolver.dart';
import '../webdav/webdav_source_repository.dart';

/// 一首歌对应的「可播音频源」。队列里的每首歌最终都会产出一个，交给
/// `_player.setAudioSources`。
class PlaybackSourceQueue {
  final List<SongEntity> songs;
  final List<AudioSource> sources;

  const PlaybackSourceQueue({required this.songs, required this.sources});
}

/// 播放地址的解析与注册，从 [PlayerService] 里抽出来。
///
/// 责任：把一首歌的 `uri`（本地路径 / WebDAV 直链 / bili 占位地址）解析成
/// 本地代理的回环地址，再包装成 just_audio 的 `AudioSource`。持有的 `_resolved`
/// TTL 缓存表是**唯一**记录「这首歌已解析到哪个代理 token」的地方，
/// 必须和它的所有读写者放在一起 —— 分开的话会拿到过期签名 URL 的 403，
/// 且只在会话开始十几分钟后才复现。
class PlaybackSourceResolver {
  static const String _logTag = 'PlaybackSourceResolver';
  static const Duration _resolvedSourceTtl = Duration(minutes: 10);

  final AudioCacheService _audioCache;
  final AudioProxyServer _proxy;
  final BiliMusicService _biliService;
  final WebDavSourceRepository _webdavSourceRepo;
  final WebDavEndpointResolver _webdavEndpointResolver;

  final Map<String, _ResolvedRemoteSource> _resolved = {};
  final Map<String, Future<Uri>> _sourceResolveInflight = {};

  PlaybackSourceResolver({
    AudioCacheService? audioCache,
    AudioProxyServer? proxy,
    BiliMusicService? biliService,
    WebDavSourceRepository? webdavSourceRepo,
    WebDavEndpointResolver? webdavEndpointResolver,
  }) : _audioCache = audioCache ?? AudioCacheService.instance,
       _proxy = proxy ?? AudioProxyServer.instance,
       _biliService = biliService ?? BiliMusicService.instance,
       _webdavSourceRepo = webdavSourceRepo ?? WebDavSourceRepository.instance,
       _webdavEndpointResolver =
           webdavEndpointResolver ?? WebDavEndpointResolver.instance;

  /// 建源阶段的并发上限。
  ///
  /// 这一步不下载音频字节，只是本地路径计算 + 代理注册（真正的网络 I/O 只有
  /// 同一 WebDAV 音源第一次探测可用地址那一次，且按 sourceId 去重，并发多少
  /// 份都只会探测一次）。上限纯粹是防止极端情况下瞬间创建过多 Future 造成
  /// 调度压力，不是在保护远端服务器。
  static const int _sourceResolveConcurrency = 24;

  /// 把队列里的每首歌解析成可播源。
  Future<PlaybackSourceQueue> buildPlaybackSourceQueue(
    List<SongEntity> songs, {
    String? forceRefreshSongId,
  }) async {
    final startedAt = DateTime.now();
    // 并发解析，而不是一首首 await 排队。
    //
    // 原来是纯串行 for 循环：几千首歌的队列（比如"顺序播放整个 WebDAV 音源"、
    // 或者恢复上次播放留下的大队列）里，每一首的 await 都要等前一首彻底完成，
    // 哪怕每首只要几毫秒，乘上几千也是实打实的几秒——期间界面点不动、切歌没
    // 反应，因为这一步跑完之前 `setAudioSources` 都还没被调用。
    //
    // 用固定大小的槽位数组按下标写回，保证 sources[i] 仍然对应 songs[i]，
    // 顺序不因并发完成顺序而错乱。
    final sources = List<AudioSource?>.filled(songs.length, null);
    for (
      var offset = 0;
      offset < songs.length;
      offset += _sourceResolveConcurrency
    ) {
      final end = (offset + _sourceResolveConcurrency).clamp(0, songs.length);
      await Future.wait([
        for (var i = offset; i < end; i++)
          sourceForSong(
            songs[i],
            forceRefresh:
                forceRefreshSongId != null && songs[i].id == forceRefreshSongId,
          ).then((source) => sources[i] = source),
      ]);
    }
    // 整库队列（几千首）在这里跑一遍的耗时直接决定了「点一首歌多久有反应」，
    // 出问题时得看得见，所以慢了就记一笔。
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed > const Duration(milliseconds: 500)) {
      AppLog.instance.d(
        _logTag,
        '解析播放队列耗时 ${elapsed.inMilliseconds}ms，共 ${songs.length} 首',
      );
    }
    return PlaybackSourceQueue(
      songs: List<SongEntity>.from(songs),
      sources: sources.cast<AudioSource>(),
    );
  }

  Future<AudioSource> sourceForSong(
    SongEntity song, {
    bool forceRefresh = false,
  }) async {
    final rawUri = (song.uri ?? '').trim();
    // B 站曲目的 uri 在库里通常是空的（直链有时效，不落库），得先走解析。
    if (!BiliMusicService.isBiliSong(song) &&
        (song.isLocal || !rawUri.startsWith('http'))) {
      return AudioSource.file(rawUri);
    }

    final local = await resolvePlayableUri(song, forceRefresh: forceRefresh);
    return AudioSource.uri(local);
  }

  Future<Uri> resolvePlayableUri(
    SongEntity song, {
    bool forceRefresh = false,
  }) async {
    final storedUri = (song.uri ?? '').trim();
    // B 站的直链带时效签名，而且解析一次就是一次网络请求 —— 建队列时挨个解析的话，
    // 一个 57 P 的合集开播前要打 57 次 playurl。这里只把「怎么解析」交给代理，
    // 真正取流时才解析，缓存键用稳定的 bili:// 占位地址而不是会变的直链。
    if (BiliMusicService.isBiliSong(song)) {
      return _registerRemoteSource(
        song,
        rawUri: storedUri.isEmpty
            ? BiliMusicService.placeholderUri(song.id)
            : storedUri,
        headers: headersFromSong(song) ?? await _biliService.headersMap(),
        forceRefresh: forceRefresh,
        resolveUri: (fresh) => _biliService
            .resolveStreamUri(song.id, forceRefresh: fresh)
            .then((url) => url == null ? null : Uri.parse(url)),
      );
    }
    if (song.isLocal || !storedUri.startsWith('http')) {
      return Uri.file(storedUri);
    }
    final rawUri = await resolveWebdavRawUri(song, storedUri);

    final headers = headersFromSong(song);
    return _registerRemoteSource(
      song,
      rawUri: rawUri,
      headers: headers,
      forceRefresh: forceRefresh,
    );
  }

  /// 预热下一首（或当前首）的解析结果，让播放时不用等。
  void warmupPlaybackSources(SongEntity current, {SongEntity? nextSong}) {
    unawaited(_warmupSource(current));
    if (nextSong != null) {
      unawaited(_warmupSource(nextSong));
    }
  }

  Future<void> _warmupSource(SongEntity song) async {
    final rawUri = (song.uri ?? '').trim();
    if (!BiliMusicService.isBiliSong(song) &&
        (song.isLocal || !rawUri.startsWith('http'))) {
      return;
    }
    try {
      await resolvePlayableUri(song);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '预热播放源失败 song=${song.title}', e, s);
    }
  }

  /// 丢弃某首歌的解析缓存（换直链 / 出错重试时用）。
  void invalidateResolvedSource(SongEntity song) {
    _resolved.remove(song.id);
    _sourceResolveInflight.remove(song.id);
    _biliService.invalidate(song.id);
    final sourceId = song.sourceId;
    if (sourceId != null) {
      _webdavEndpointResolver.invalidate(sourceId);
    }
  }

  Map<String, String>? headersFromSong(SongEntity song) {
    final raw = (song.headersJson ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
      return null;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '解析歌曲自带请求头 JSON 失败 songId=${song.id}', e, s);
      return null;
    }
  }

  /// If [song] belongs to a WebDAV source with multiple addresses (e.g. LAN
  /// at home, remote-access tunnel while away), rewrites [rawUri]'s host to
  /// whichever address currently answers. Leaves [rawUri] untouched for
  /// everything else (single-address sources, Navidrome, local files).
  Future<String> resolveWebdavRawUri(SongEntity song, String rawUri) async {
    final sourceId = song.sourceId;
    if (sourceId == null || !sourceId.startsWith('webdav')) return rawUri;
    try {
      final sources = await _webdavSourceRepo.loadSources();
      WebDavSource? source;
      for (final s in sources) {
        if (s.id == sourceId) {
          source = s;
          break;
        }
      }
      if (source == null || source.allEndpoints.length <= 1) return rawUri;
      final active = await _webdavEndpointResolver.resolveActiveEndpoint(
        source,
      );
      if (active == null) return rawUri;
      return _webdavEndpointResolver.rewriteHost(rawUri, active).toString();
    } catch (e, s) {
      AppLog.instance.w(
        _logTag,
        '解析 WebDAV 可用地址失败 sourceId=$sourceId，回退到原始地址',
        e,
        s,
      );
      return rawUri;
    }
  }

  /// 把一条远程地址注册到本地代理，返回 `http://127.0.0.1:.../stream?token=...`。
  /// just_audio 永远只看到这个回环地址，鉴权头不会离开本进程。
  ///
  /// 传了 [resolveUri] 时 [rawUri] 只当作缓存键和去重键用，真正的上游地址由代理
  /// 在首次取流时调 [resolveUri] 拿。
  Future<Uri> _registerRemoteSource(
    SongEntity song, {
    required String rawUri,
    required Map<String, String>? headers,
    required bool forceRefresh,
    Future<Uri?> Function(bool forceRefresh)? resolveUri,
  }) async {
    final headersKey = _headersFingerprint(headers);
    if (forceRefresh) {
      invalidateResolvedSource(song);
    }

    final cached = _resolved[song.id];
    if (cached != null &&
        cached.rawUri == rawUri &&
        cached.headersFingerprint == headersKey &&
        !cached.isExpired) {
      return cached.proxyUri;
    }

    final inflight = _sourceResolveInflight[song.id];
    if (inflight != null) return inflight;

    final future = () async {
      final remoteUri = _getSafeUri(rawUri);
      final finalRemoteUri = remoteUri ?? Uri.parse(rawUri);
      final uriStr = finalRemoteUri.toString();
      final cacheFile = await _audioCache.getCacheFile(
        uri: uriStr,
        headers: headers,
      );
      final proxyUri = await _proxy.registerSource(
        uri: resolveUri == null ? finalRemoteUri : null,
        resolveUri: resolveUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
          // 歌曲自带的头放最后：B 站的 Referer/Cookie 必须能覆盖上面的默认值，
          // 否则 CDN 直接 403。
          ...?headers,
        },
        cacheFile: cacheFile,
      );
      _resolved[song.id] = _ResolvedRemoteSource(
        rawUri: rawUri,
        headersFingerprint: headersKey,
        proxyUri: proxyUri,
        resolvedAt: DateTime.now(),
      );
      return proxyUri;
    }();

    _sourceResolveInflight[song.id] = future;
    future.whenComplete(() => _sourceResolveInflight.remove(song.id));
    return future;
  }

  String _headersFingerprint(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    final pairs = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return pairs.map((e) => '${e.key}=${e.value}').join('&');
  }

  Uri? _getSafeUri(String uriStr) {
    try {
      final uri = Uri.parse(uriStr);
      // Heuristic: If path contains %25 (encoded %), it might be double encoded (e.g. %2520 instead of %20).
      // We want to decode it so that the resulting Uri uses proper single encoding.
      if (uri.path.contains('%25')) {
        try {
          return Uri.parse(Uri.decodeFull(uriStr));
        } catch (_) {
          return uri;
        }
      }
      return uri;
    } catch (_) {
      try {
        return Uri.parse(Uri.encodeFull(uriStr));
      } catch (_) {
        return null;
      }
    }
  }
}

class _ResolvedRemoteSource {
  final String rawUri;
  final String headersFingerprint;
  final Uri proxyUri;
  final DateTime resolvedAt;

  const _ResolvedRemoteSource({
    required this.rawUri,
    required this.headersFingerprint,
    required this.proxyUri,
    required this.resolvedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(resolvedAt) >
      PlaybackSourceResolver._resolvedSourceTtl;
}
