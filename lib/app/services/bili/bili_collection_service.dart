import 'dart:async';
import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/song_state.dart';
import '../log/log.dart';
import '../player_service.dart';
import 'bili_music_service.dart';

/// 一个由用户保存在 NagoMusic 内的 B 站视频合集。
///
/// 保存完整的分 P 元数据，所以收藏之后不必再次搜索；播放地址仍由
/// [BiliMusicService] 在真正播放时按需解析，避免持久化会过期的链接。
@immutable
class BiliVideoCollection {
  final BiliVideoDetail detail;
  final int addedAtMs;
  final int lastCid;
  final int positionMs;
  final int lastPlayedAtMs;

  const BiliVideoCollection({
    required this.detail,
    required this.addedAtMs,
    this.lastCid = 0,
    this.positionMs = 0,
    this.lastPlayedAtMs = 0,
  });

  BiliVideo get video => detail.video;

  int get resumeIndex => detail.parts.indexWhere((part) => part.cid == lastCid);

  bool get hasProgress => resumeIndex >= 0;

  Duration get resumePosition =>
      Duration(milliseconds: positionMs < 0 ? 0 : positionMs);

  BiliVideoCollection copyWith({
    BiliVideoDetail? detail,
    int? lastCid,
    int? positionMs,
    int? lastPlayedAtMs,
  }) {
    return BiliVideoCollection(
      detail: detail ?? this.detail,
      addedAtMs: addedAtMs,
      lastCid: lastCid ?? this.lastCid,
      positionMs: positionMs ?? this.positionMs,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
    );
  }

  Map<String, Object> toJson() {
    final video = detail.video;
    return {
      'video': {
        'bvid': video.bvid,
        'aid': video.aid,
        'title': video.title,
        'author': video.author,
        'cover': video.cover,
        'durationSec': video.durationSec,
        'partCount': video.partCount,
      },
      'parts': [
        for (final part in detail.parts)
          {
            'cid': part.cid,
            'index': part.index,
            'title': part.title,
            'durationSec': part.durationSec,
          },
      ],
      'addedAtMs': addedAtMs,
      'lastCid': lastCid,
      'positionMs': positionMs,
      'lastPlayedAtMs': lastPlayedAtMs,
    };
  }

  factory BiliVideoCollection.fromJson(Map<String, dynamic> json) {
    final rawVideo = json['video'];
    if (rawVideo is! Map) {
      throw const FormatException('Missing B站 video metadata');
    }
    final videoJson = rawVideo.cast<String, dynamic>();
    final bvid = (videoJson['bvid'] ?? '').toString().trim();
    if (bvid.isEmpty) throw const FormatException('Missing bvid');
    final video = BiliVideo(
      bvid: bvid,
      aid: _intValue(videoJson['aid']),
      title: (videoJson['title'] ?? '').toString(),
      author: (videoJson['author'] ?? '').toString(),
      cover: BiliVideo.normalizeCover(videoJson['cover']),
      durationSec: _intValue(videoJson['durationSec']),
      partCount: _intValue(videoJson['partCount']),
    );
    final rawParts = json['parts'];
    final parts = rawParts is List
        ? rawParts
              .whereType<Map>()
              .map((raw) {
                final part = raw.cast<String, dynamic>();
                return BiliPart(
                  cid: _intValue(part['cid']),
                  index: _intValue(part['index'], fallback: 1),
                  title: (part['title'] ?? '').toString(),
                  durationSec: _intValue(part['durationSec']),
                );
              })
              .where((part) => part.cid > 0)
              .toList()
        : <BiliPart>[];
    if (parts.isEmpty) throw const FormatException('Missing B站 parts');
    return BiliVideoCollection(
      detail: BiliVideoDetail(video: video, parts: parts),
      addedAtMs: _intValue(json['addedAtMs']),
      lastCid: _intValue(json['lastCid']),
      positionMs: _intValue(json['positionMs']),
      lastPlayedAtMs: _intValue(json['lastPlayedAtMs']),
    );
  }

  static int _intValue(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }
}

/// 本地 B 站视频合集收藏与续播进度。
class BiliCollectionService {
  static const String _logTag = 'BiliCollectionService';

  static const String prefsKey = 'bili_video_collections_v1';

  static final BiliCollectionService instance = BiliCollectionService(
    player: PlayerService.instance,
  );

  final PlayerService? _player;
  final ValueNotifier<List<BiliVideoCollection>> collections = ValueNotifier(
    const [],
  );

  Future<void>? _loadFuture;
  Future<void> _writeTail = Future<void>.value();
  Timer? _progressTimer;
  PlaybackSnapshot? _pendingSnapshot;

  /// [player] 留空时可作为纯存储对象使用，便于单元测试。
  BiliCollectionService({PlayerService? player}) : _player = player {
    player?.snapshot.addListener(_handlePlayerSnapshot);
  }

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      collections.value = const [];
      return;
    }
    final restored = <BiliVideoCollection>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          try {
            restored.add(
              BiliVideoCollection.fromJson(item.cast<String, dynamic>()),
            );
          } catch (e, s) {
            AppLog.instance.w(_logTag, '解析单条B站收藏失败，已跳过', e, s);
          }
        }
      }
    } catch (e, s) {
      AppLog.instance.w(_logTag, '解析B站收藏列表整体失败，回退为空列表', e, s);
      // 整体损坏时回退为空列表，后续新增会覆盖坏数据。
    }
    restored.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
    collections.value = List.unmodifiable(restored);
  }

  BiliVideoCollection? find(String bvid) {
    for (final collection in collections.value) {
      if (collection.video.bvid == bvid) return collection;
    }
    return null;
  }

  bool contains(String bvid) => find(bvid) != null;

  Future<void> add(BiliVideoDetail detail) async {
    await ensureLoaded();
    if (detail.video.bvid.trim().isEmpty || detail.parts.isEmpty) return;
    final current = find(detail.video.bvid);
    final next = current == null
        ? BiliVideoCollection(
            detail: detail,
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
          )
        : current.copyWith(detail: detail);
    collections.value = List.unmodifiable([
      next,
      for (final item in collections.value)
        if (item.video.bvid != detail.video.bvid) item,
    ]);
    await _persist();
  }

  Future<void> remove(String bvid) async {
    await ensureLoaded();
    collections.value = List.unmodifiable(
      collections.value.where((item) => item.video.bvid != bvid),
    );
    await _persist();
  }

  /// 记录一个已收藏合集的分 P 与分 P 内位置。
  Future<void> recordPlayback(SongEntity song, Duration position) async {
    final parsed = BiliMusicService.parseSongId(song.id);
    if (parsed == null) return;
    await ensureLoaded();
    final bvid = parsed.$1;
    final cid = parsed.$2;
    final index = collections.value.indexWhere(
      (item) => item.video.bvid == bvid,
    );
    if (index < 0) return;
    final collection = collections.value[index];
    if (!collection.detail.parts.any((part) => part.cid == cid)) return;
    final positionMs = position.inMilliseconds.clamp(
      0,
      song.durationMs ?? position.inMilliseconds,
    );
    if (collection.lastCid == cid &&
        (collection.positionMs - positionMs).abs() < 500) {
      return;
    }
    final updated = collection.copyWith(
      lastCid: cid,
      positionMs: positionMs,
      lastPlayedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final next = [...collections.value];
    next[index] = updated;
    collections.value = List.unmodifiable(next);
    await _persist();
  }

  void _handlePlayerSnapshot() {
    final snapshot = _player?.snapshot.value;
    if (snapshot == null) return;
    final song = snapshot.song;
    if (song == null || !BiliMusicService.isBiliSong(song)) {
      _flushPendingProgress();
      return;
    }

    final previous = _pendingSnapshot;
    if (previous?.song?.id != null && previous!.song!.id != song.id) {
      _progressTimer?.cancel();
      _progressTimer = null;
      unawaited(_recordSnapshot(previous));
    }
    _pendingSnapshot = snapshot;
    if (!snapshot.isPlaying) {
      _flushPendingProgress();
      return;
    }
    if (_progressTimer?.isActive ?? false) return;
    _progressTimer = Timer(const Duration(seconds: 1), _flushPendingProgress);
  }

  void _flushPendingProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    final snapshot = _pendingSnapshot;
    _pendingSnapshot = null;
    if (snapshot != null) unawaited(_recordSnapshot(snapshot));
  }

  Future<void> _recordSnapshot(PlaybackSnapshot snapshot) async {
    final song = snapshot.song;
    if (song == null) return;
    await recordPlayback(song, snapshot.position);
  }

  Future<void> _persist() {
    final raw = jsonEncode(
      collections.value.map((item) => item.toJson()).toList(),
    );
    _writeTail = _writeTail.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, raw);
    });
    return _writeTail;
  }

  @visibleForTesting
  void dispose() {
    _progressTimer?.cancel();
    _player?.snapshot.removeListener(_handlePlayerSnapshot);
    collections.dispose();
  }
}
