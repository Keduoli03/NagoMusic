import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:media_cache/media_cache.dart';
import 'package:photo_manager/photo_manager.dart';

import 'log/log.dart';
import 'native_audio_thumbnail_service.dart';

class ArtworkService {
  ArtworkService._();

  static final ArtworkService instance = ArtworkService._();

  static const String _logTag = 'ArtworkService';

  static const bool _debugArtwork = false;
  // 条数上限只是次要保险，真正的约束是下面的字节预算 —— 缩略图和内嵌原图
  // 体积差两个数量级，按条数根本控不住内存。
  static const int _maxCache = 400;
  // 压缩字节的总预算。24MB 足够存下几百张缩略图，同时把内嵌原图（1~3MB 一张）
  // 限制在十来张以内，不至于让播放历史一路把内存拖上去。
  static const int _maxCacheBytes = 24 * 1024 * 1024;
  static const int _maxConcurrent = 6;

  /// [_bytesCache] 里所有非 null 条目的字节数之和。
  int _cachedBytes = 0;

  final LinkedHashMap<String, Uint8List?> _bytesCache =
      LinkedHashMap<String, Uint8List?>();
  final Map<String, Future<Uint8List?>> _loadingFutures =
      <String, Future<Uint8List?>>{};
  final Map<String, String?> _assetIdCache = <String, String?>{};
  final Map<String, Future<String?>> _assetIdFutures =
      <String, Future<String?>>{};
  final List<_ArtworkRequest> _queue = <_ArtworkRequest>[];
  int _active = 0;

  String _normalizePath(String path) => path.replaceAll('\\', '/').trim();

  Future<String?> resolveLocalAssetId(String? uri) async {
    final trimmedUri = _normalizePath(uri ?? '');
    if (trimmedUri.isEmpty) return null;
    if (_assetIdCache.containsKey(trimmedUri)) {
      if (kDebugMode && _debugArtwork) {
        debugPrint(
          '[ArtworkService] resolveLocalAssetId cache uri=$trimmedUri asset=${_assetIdCache[trimmedUri]}',
        );
      }
      return _assetIdCache[trimmedUri];
    }
    final inflight = _assetIdFutures[trimmedUri];
    if (inflight != null) return inflight;
    final future = _resolveLocalAssetIdInternal(trimmedUri);
    _assetIdFutures[trimmedUri] = future;
    final resolved = await future;
    _assetIdFutures.remove(trimmedUri);
    _assetIdCache[trimmedUri] = resolved;
    if (kDebugMode && _debugArtwork) {
      debugPrint(
        '[ArtworkService] resolveLocalAssetId result uri=$trimmedUri asset=$resolved',
      );
    }
    return resolved;
  }

  /// 同步查一眼内存缓存，命中就直接给出字节。
  ///
  /// [loadArtworkBytes] 是 async 的，**哪怕内存缓存命中也要等一个 microtask**，
  /// 而那已经是当前这一帧画完之后了。调用方于是必然先画一帧占位图再换成封面 ——
  /// 首页切换筛选时六个封面同时闪一下，观感上就是「卡」。有了这个同步入口，
  /// 已经缓存过的封面可以在 build 之前就填好，一帧都不闪。
  ///
  /// 返回 null 有两种含义：没缓存过，或者缓存里记的就是「这首没有内嵌封面」。
  /// 调用方不需要区分 —— 拿不到就照常走 [loadArtworkBytes]。
  Uint8List? peekArtworkBytes({
    required String? uri,
    required String? localAssetId,
    required bool isLocal,
    required bool preferOriginal,
  }) {
    if (!isLocal) return null;
    final trimmedUri = (uri ?? '').trim();
    if (trimmedUri.isEmpty) return null;
    final trimmedAssetId = (localAssetId ?? '').trim();
    final cacheBase = trimmedAssetId.isNotEmpty
        ? 'asset:$trimmedAssetId'
        : trimmedUri;
    // 不做 LRU 提升：peek 是渲染路径上的旁路查询，不该影响淘汰顺序。
    return _bytesCache[preferOriginal ? '$cacheBase|original' : cacheBase];
  }

  Future<Uint8List?> loadArtworkBytes({
    required String? uri,
    required String? localCoverPath,
    required String? localAssetId,
    required bool isLocal,
    required bool preferOriginal,
  }) async {
    final trimmedCover = (localCoverPath ?? '').trim();
    // 播放页以原图展示封面时，需要把外置封面也纳入同一条字节加载链路。
    // 这样 [ArtworkWidget.keepPreviousUntilLoaded] 才能在新文件解码完成前保留
    // 上一首的真实画面；若直接切到 Image.file，新图还没解码的那一帧会露出
    // 背景色，切歌时就像闪屏一样。
    if (preferOriginal && trimmedCover.isNotEmpty) {
      try {
        final file = File(trimmedCover);
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {
        // 外置封面读失败后继续走内嵌封面的正常兜底。
      }
    }
    if (!preferOriginal && trimmedCover.isNotEmpty) {
      final file = File(trimmedCover);
      if (await file.exists()) {
        if (kDebugMode && _debugArtwork) {
          debugPrint(
            '[ArtworkService] loadArtworkBytes local cache exists uri=${uri ?? ''} cover=$trimmedCover',
          );
        }
        return null;
      }
    }

    if (!isLocal) return null;
    final trimmedUri = (uri ?? '').trim();
    var trimmedAssetId = (localAssetId ?? '').trim();
    if (trimmedUri.isEmpty) return null;

    if (kDebugMode && _debugArtwork) {
      debugPrint(
        '[ArtworkService] loadArtworkBytes request uri=$trimmedUri asset=$trimmedAssetId preferOriginal=$preferOriginal isLocal=$isLocal',
      );
    }

    final cacheBase = trimmedAssetId.isNotEmpty
        ? 'asset:$trimmedAssetId'
        : trimmedUri;
    final cacheKey = preferOriginal ? '$cacheBase|original' : cacheBase;
    if (_bytesCache.containsKey(cacheKey)) {
      final cached = _bytesCache.remove(cacheKey);
      _bytesCache[cacheKey] = cached;
      if (kDebugMode && _debugArtwork) {
        debugPrint('[ArtworkService] loadArtworkBytes memory key=$cacheKey');
      }
      return cached;
    }

    final inflight = _loadingFutures[cacheKey];
    if (inflight != null) return inflight;

    final completer = Completer<Uint8List?>();
    _loadingFutures[cacheKey] = completer.future;
    _queue.add(
      _ArtworkRequest(
        trimmedUri,
        trimmedAssetId,
        cacheKey,
        preferOriginal,
        completer,
      ),
    );
    _drainQueue();

    return completer.future.whenComplete(() {
      _loadingFutures.remove(cacheKey);
    });
  }

  Future<String?> _resolveLocalAssetIdInternal(String normalizedUri) async {
    try {
      final ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.audio,
            mediaLocation: false,
          ),
        ),
      );
      if (!ps.isAuth) return null;

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.audio,
      );
      final seenIds = <String>{};
      const pageSize = 200;
      for (final album in albums) {
        final count = await album.assetCountAsync;
        var start = 0;
        while (start < count) {
          final end = (start + pageSize).clamp(0, count);
          final entities = await album.getAssetListRange(
            start: start,
            end: end,
          );
          if (entities.isEmpty) break;
          for (final entity in entities) {
            if (!seenIds.add(entity.id)) continue;
            final file = await entity.file;
            if (file == null) continue;
            if (_normalizePath(file.path) == normalizedUri) {
              if (kDebugMode && _debugArtwork) {
                debugPrint(
                  '[ArtworkService] resolveLocalAssetId matched uri=$normalizedUri asset=${entity.id}',
                );
              }
              return entity.id;
            }
          }
          start = end;
        }
      }
      return null;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '解析本地资源 assetId 失败 uri=$normalizedUri', e, s);
      return null;
    }
  }

  void clearByUri(String? uri) {
    final trimmed = (uri ?? '').trim();
    if (trimmed.isEmpty) return;
    _removeKey(trimmed);
    _removeKey('$trimmed|original');
    // 有 localAssetId 时缓存键是 'asset:<id>' 而不是 uri（见 loadArtworkBytes），
    // 只删 uri 那两条的话本地歌曲的缓存根本删不掉，表现为「刮削完封面还是旧的」。
    final assetId = _assetIdCache[_normalizePath(trimmed)];
    if (assetId != null && assetId.isNotEmpty) {
      _removeKey('asset:$assetId');
      _removeKey('asset:$assetId|original');
    }
  }

  /// 删一条并同步扣掉它的字节数。所有从 [_bytesCache] 移除的地方都要走这里，
  /// 否则 [_cachedBytes] 会越漂越大，最后把缓存饿死（一直以为超预算而疯狂淘汰）。
  void _removeKey(String key) {
    final removed = _bytesCache.remove(key);
    if (removed != null) _cachedBytes -= removed.length;
  }

  void _remember(String cacheKey, Uint8List? bytes) {
    _removeKey(cacheKey);
    _bytesCache[cacheKey] = bytes;
    if (bytes != null) _cachedBytes += bytes.length;
    _evict();
  }

  /// 按**字节总量**淘汰，条数只作次要上限。
  ///
  /// 以前只按条数淘汰（400 条），注释里按「320px 缩略图 ~20KB」估的 ~10MB。但
  /// `|original` 那些条目存的是内嵌原图，一张 1~3MB —— 播过一百首歌，光这个 map
  /// 就能吃掉几百兆。设备日志里进程 RSS 到过 717MB，这里是重要来源之一。
  void _evict() {
    while (_bytesCache.isNotEmpty &&
        (_cachedBytes > _maxCacheBytes || _bytesCache.length > _maxCache)) {
      _removeKey(_bytesCache.keys.first);
    }
    // 负数只可能来自「同一份字节被记了两次」这类 bug，兜一下别让它越漂越远。
    if (_cachedBytes < 0) _cachedBytes = 0;
  }

  void _drainQueue() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeLast();
      _active += 1;
      _readArtworkBytes(
            task.uri,
            assetId: task.assetId,
            preferOriginal: task.preferOriginal,
          )
          .then((bytes) {
            _remember(task.cacheKey, bytes);
            if (!task.completer.isCompleted) {
              task.completer.complete(bytes);
            }
          })
          .catchError((_) {
            _remember(task.cacheKey, null);
            if (!task.completer.isCompleted) {
              task.completer.complete(null);
            }
          })
          .whenComplete(() {
            _active -= 1;
            _drainQueue();
          });
    }
  }

  static Future<Uint8List?> _readArtworkBytes(
    String uri, {
    required String assetId,
    required bool preferOriginal,
  }) async {
    try {
      if (!preferOriginal) {
        final nativeThumb = await NativeAudioThumbnailService.instance
            .loadThumbnail(uri, size: 320);
        if (nativeThumb != null && nativeThumb.isNotEmpty) {
          if (kDebugMode && _debugArtwork) {
            debugPrint(
              '[ArtworkService] native platform thumb uri=$uri bytes=${nativeThumb.length}',
            );
          }
          return nativeThumb;
        }
      }

      if (assetId.isNotEmpty && !preferOriginal) {
        final entity = await AssetEntity.fromId(assetId);
        if (entity != null) {
          final thumb = await entity.thumbnailDataWithSize(
            const ThumbnailSize(320, 320),
          );
          if (thumb != null && thumb.isNotEmpty) {
            if (kDebugMode && _debugArtwork) {
              debugPrint(
                '[ArtworkService] native thumb uri=$uri asset=$assetId bytes=${thumb.length}',
              );
            }
            return thumb;
          }
          if (kDebugMode && _debugArtwork) {
            debugPrint(
              '[ArtworkService] native thumb empty uri=${HttpUtils.redactUrl(uri)} asset=$assetId',
            );
          }
        } else if (kDebugMode && _debugArtwork) {
          debugPrint(
            '[ArtworkService] asset missing uri=${HttpUtils.redactUrl(uri)} asset=$assetId',
          );
        }
      }

      final original = await compute(_readEmbeddedArtworkIsolate, uri);
      if (original == null || original.isEmpty) return null;
      if (kDebugMode && _debugArtwork) {
        debugPrint(
          '[ArtworkService] embedded art uri=$uri bytes=${original.length} preferOriginal=$preferOriginal',
        );
      }
      if (preferOriginal) {
        return original;
      }
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          original,
          minWidth: 300,
          minHeight: 300,
          quality: 85,
        );
        if (compressed.isNotEmpty) {
          return compressed;
        }
      } catch (_) {}
      return original;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '读取封面失败 uri=$uri asset=$assetId', e, s);
      return null;
    }
  }
}

/// 在后台 isolate 上把内嵌封面读出来。
///
/// `readMetadata` 和 `extractOggVorbisComments` 都是**同步**的，而且要把整个音频
/// 文件读进来解析。带 1~3MB 内嵌大图的歌在 UI isolate 上做一次就是几十毫秒，
/// 而一帧预算只有 16ms —— 表现就是播放页每次切歌掉几帧。
///
/// `tag_probe_service.dart` 的 `_readMetadataIsolate` 早就是这么跑的（同一个库、
/// 同样开着 `getImage`），这里只是把最后一个漏掉的调用点补齐。
///
/// 只收路径、只回字节，两端都是可跨 isolate 传的类型。
Uint8List? _readEmbeddedArtworkIsolate(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;

    var original = Uint8List(0);
    try {
      final metadata = readMetadata(file, getImage: true);
      if (metadata.pictures.isNotEmpty) {
        original = metadata.pictures.first.bytes;
      }
    } catch (_) {
      // 解析抛异常对 OGG 来说是常态，不能就此放弃 —— 下面还有自己的兜底提取器。
      // （改成 isolate 之前这个异常会被最外层 catch 吞掉，直接跳过 OGG 兜底。）
    }

    // The bundled reader misses OGG/Opus covers (METADATA_BLOCK_PICTURE in a
    // Vorbis comment) — fall back to our own extractor for those.
    if (original.isEmpty && isOggPath(path)) {
      final ogg = extractOggVorbisComments(path, includeArtwork: true);
      final oggArt = ogg?.artwork;
      if (oggArt != null && oggArt.isNotEmpty) {
        original = oggArt;
      }
    }
    return original.isEmpty ? null : original;
  } catch (_) {
    return null;
  }
}

class _ArtworkRequest {
  final String uri;
  final String assetId;
  final String cacheKey;
  final bool preferOriginal;
  final Completer<Uint8List?> completer;

  _ArtworkRequest(
    this.uri,
    this.assetId,
    this.cacheKey,
    this.preferOriginal,
    this.completer,
  );
}
