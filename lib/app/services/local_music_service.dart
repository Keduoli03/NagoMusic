import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_cache/media_cache.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/song_state.dart';
import 'artwork_cache_helper.dart';
import 'db/dao/song_dao.dart';
import 'log/log.dart';
import 'lyrics/lyrics_repository.dart';
import '../services/scan_types.dart';

class LocalSourceSettings {
  final bool useSystemLibrary;
  final int minDurationMs;
  final List<String> includeAlbumIds;
  final List<String> includePaths;
  final int lastScanCount;
  final bool cacheArtwork;
  final bool readFullTagsOnScan;
  final int localMetadataConcurrency;

  const LocalSourceSettings({
    required this.useSystemLibrary,
    required this.minDurationMs,
    required this.includeAlbumIds,
    required this.includePaths,
    required this.lastScanCount,
    required this.cacheArtwork,
    required this.readFullTagsOnScan,
    required this.localMetadataConcurrency,
  });

  factory LocalSourceSettings.defaults() {
    return const LocalSourceSettings(
      useSystemLibrary: true,
      minDurationMs: 0,
      includeAlbumIds: [],
      includePaths: [],
      lastScanCount: 0,
      cacheArtwork: false,
      readFullTagsOnScan: false,
      localMetadataConcurrency: 6,
    );
  }

  LocalSourceSettings copyWith({
    bool? useSystemLibrary,
    int? minDurationMs,
    List<String>? includeAlbumIds,
    List<String>? includePaths,
    int? lastScanCount,
    bool? cacheArtwork,
    bool? readFullTagsOnScan,
    int? localMetadataConcurrency,
  }) {
    return LocalSourceSettings(
      useSystemLibrary: useSystemLibrary ?? this.useSystemLibrary,
      minDurationMs: minDurationMs ?? this.minDurationMs,
      includeAlbumIds: includeAlbumIds ?? this.includeAlbumIds,
      includePaths: includePaths ?? this.includePaths,
      lastScanCount: lastScanCount ?? this.lastScanCount,
      cacheArtwork: cacheArtwork ?? this.cacheArtwork,
      readFullTagsOnScan: readFullTagsOnScan ?? this.readFullTagsOnScan,
      localMetadataConcurrency:
          localMetadataConcurrency ?? this.localMetadataConcurrency,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'useSystemLibrary': useSystemLibrary,
      'minDurationMs': minDurationMs,
      'includeAlbumIds': includeAlbumIds,
      'includePaths': includePaths,
      'lastScanCount': lastScanCount,
      'cacheArtwork': cacheArtwork,
      'readFullTagsOnScan': readFullTagsOnScan,
      'localMetadataConcurrency': localMetadataConcurrency,
    };
  }

  factory LocalSourceSettings.fromJson(Map<String, dynamic> json) {
    return LocalSourceSettings(
      useSystemLibrary: json['useSystemLibrary'] as bool? ?? true,
      minDurationMs: json['minDurationMs'] as int? ?? 0,
      includeAlbumIds:
          (json['includeAlbumIds'] as List<dynamic>?)?.cast<String>() ?? [],
      includePaths:
          (json['includePaths'] as List<dynamic>?)?.cast<String>() ?? [],
      lastScanCount: json['lastScanCount'] as int? ?? 0,
      cacheArtwork: json['cacheArtwork'] as bool? ?? false,
      readFullTagsOnScan: json['readFullTagsOnScan'] as bool? ?? false,
      localMetadataConcurrency: json['localMetadataConcurrency'] as int? ?? 6,
    );
  }
}

class _LocalScanCandidate {
  final String path;
  final String? assetId;
  final int? durationMs;
  final String? titleHint;
  final String? albumHint;

  const _LocalScanCandidate({
    required this.path,
    required this.assetId,
    required this.durationMs,
    required this.titleHint,
    required this.albumHint,
  });
}

class LocalMusicService {
  static const String _logTag = 'LocalMusicService';
  static const String _prefsKey = 'local_source_settings';
  final SongDao _songDao = SongDao();
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final TagProbeService _tagProbe = TagProbeService.instance;

  Future<LocalSourceSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return LocalSourceSettings.defaults();
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return LocalSourceSettings.fromJson(data);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '本地音乐来源设置解析失败，已回退默认值', e, s);
      return LocalSourceSettings.defaults();
    }
  }

  Future<void> saveSettings(LocalSourceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
  }

  Future<void> saveLastScanCount(int count) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(lastScanCount: count));
  }

  Future<int> getLocalSongCount() async {
    return _songDao.countBySource('local');
  }

  Future<int> cleanupShortLocalSongs(int minDurationMs) async {
    if (minDurationMs <= 0) return 0;
    var removed = await _songDao.deleteBySourceAndMaxDuration(
      sourceId: 'local',
      maxDurationMs: minDurationMs,
    );

    final localSongs = await _songDao.fetchAll(sourceId: 'local');
    final unknownDurationSongs = localSongs.where((song) {
      final uri = (song.uri ?? '').trim();
      return song.durationMs == null && uri.isNotEmpty;
    }).toList();
    if (unknownDurationSongs.isEmpty) {
      return removed;
    }

    final resolvedSongs = <SongEntity>[];
    final deleteIds = <String>[];

    for (final song in unknownDurationSongs) {
      final uri = (song.uri ?? '').trim();
      if (uri.isEmpty) continue;
      final file = File(uri);
      if (!await file.exists()) continue;

      final tagInfo = await _tagProbe.probeLocalBasicTags(uri: uri);
      final durationMs = tagInfo?.durationMs;
      if (durationMs == null || durationMs <= 0) {
        continue;
      }
      if (durationMs < minDurationMs) {
        deleteIds.add(song.id);
        continue;
      }
      resolvedSongs.add(song.copyWith(durationMs: durationMs));
    }

    if (resolvedSongs.isNotEmpty) {
      await _songDao.upsertSongs(resolvedSongs);
    }
    if (deleteIds.isNotEmpty) {
      removed += await _songDao.deleteByIds(deleteIds);
    }
    return removed;
  }

  Future<List<AssetPathEntity>> loadAudioAlbums({int? minDurationMs}) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.audio,
          mediaLocation: false,
        ),
      ),
    );
    if (!ps.isAuth) {
      PhotoManager.openSetting();
      return [];
    }

    final filterOption = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.updateDate, asc: false)],
    );
    if (minDurationMs != null && minDurationMs > 0) {
      filterOption.setOption(
        AssetType.audio,
        FilterOption(
          durationConstraint: DurationConstraint(
            min: Duration(milliseconds: minDurationMs),
          ),
        ),
      );
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.audio,
      filterOption: filterOption,
    );
    return paths.where((p) => !p.isAll).toList();
  }

  Future<ScanResult> scan({
    required LocalSourceSettings settings,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<ScanProgress> onProgress,
  }) async {
    var processed = 0;
    var added = 0;
    final scannedSongs = <SongEntity>[];
    final existingSongs = await _songDao.fetchAll(sourceId: 'local');
    final existingById = {for (final song in existingSongs) song.id: song};
    final existingIds = existingById.keys.toSet();
    final seenPaths = <String>{};
    final candidates = <_LocalScanCandidate>[];
    final customFiles = await _collectCustomFiles(
      settings.includePaths,
      isCancelled,
    );
    var total = 0;
    final progressClock = Stopwatch()..start();
    var lastProgressAtMs = -1000;
    var lastProgressProcessed = -1;

    void reportProgress({bool force = false}) {
      if (!force && processed == lastProgressProcessed) return;
      final elapsedMs = progressClock.elapsedMilliseconds;
      final enoughTime = elapsedMs - lastProgressAtMs >= 200;
      final enoughSongs = processed - lastProgressProcessed >= 20;
      if (!force && !enoughTime && !enoughSongs) return;
      lastProgressAtMs = elapsedMs;
      lastProgressProcessed = processed;
      onProgress(
        ScanProgress(processed: processed, added: added, total: total),
      );
    }

    List<AssetPathEntity> selectedAlbums = [];
    final includeSet = settings.includeAlbumIds.toSet();
    final needAlbumScan = settings.useSystemLibrary || includeSet.isNotEmpty;
    if (needAlbumScan) {
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.audio,
            mediaLocation: false,
          ),
        ),
      );
      if (ps.isAuth) {
        final albums = await loadAudioAlbums(
          minDurationMs: settings.minDurationMs,
        );
        selectedAlbums = settings.useSystemLibrary
            ? albums
            : albums.where((album) => includeSet.contains(album.id)).toList();
      } else {
        PhotoManager.openSetting();
      }
    }

    for (final album in selectedAlbums) {
      if (isCancelled()) break;
      final count = await album.assetCountAsync;
      var start = 0;
      const pageSize = 200;
      while (start < count) {
        if (isCancelled()) break;
        final end = (start + pageSize).clamp(0, count);
        final entities = await album.getAssetListRange(start: start, end: end);
        if (entities.isEmpty) break;
        for (final entity in entities) {
          if (isCancelled()) break;
          if (settings.minDurationMs > 0 &&
              entity.duration * 1000 < settings.minDurationMs) {
            continue;
          }
          final File? file = await entity.file;
          if (file == null) {
            continue;
          }
          if (!seenPaths.add(file.path)) {
            continue;
          }
          candidates.add(
            _LocalScanCandidate(
              path: file.path,
              assetId: entity.id,
              durationMs: (entity.duration * 1000).round(),
              titleHint: entity.title,
              albumHint: album.name,
            ),
          );
        }
        start = end;
      }
    }

    for (final file in customFiles) {
      if (isCancelled()) break;
      if (!seenPaths.add(file.path)) {
        continue;
      }
      candidates.add(
        _LocalScanCandidate(
          path: file.path,
          assetId: null,
          durationMs: null,
          titleHint: null,
          albumHint: null,
        ),
      );
    }

    total = candidates.length;
    reportProgress(force: true);

    final int concurrency = settings.localMetadataConcurrency.clamp(1, 12);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled()) return;
        final idx = nextIndex;
        if (idx >= candidates.length) return;
        nextIndex += 1;
        final candidate = candidates[idx];
        final file = File(candidate.path);
        if (!await file.exists()) {
          processed += 1;
          reportProgress();
          continue;
        }
        final stat = await file.stat();
        final modifiedMs = stat.modified.millisecondsSinceEpoch;
        final existing = existingById[candidate.path];
        final unchanged =
            existing != null && existing.fileModifiedMs == modifiedMs;

        if (unchanged) {
          if (settings.minDurationMs > 0 &&
              existing.durationMs != null &&
              existing.durationMs! < settings.minDurationMs) {
            processed += 1;
            reportProgress();
            continue;
          }
          final trimmedAssetId = (candidate.assetId ?? '').trim();
          final existingAssetId = (existing.localAssetId ?? '').trim();
          final existingCoverPath = (existing.localCoverPath ?? '').trim();
          String? nextCoverPath = existing.localCoverPath;
          if (existingCoverPath.isEmpty && trimmedAssetId.isNotEmpty) {
            nextCoverPath = await _cacheAssetThumbnail(
              assetId: trimmedAssetId,
              fileModifiedMs: modifiedMs,
            );
          }
          final nextSong =
              (trimmedAssetId.isNotEmpty &&
                      trimmedAssetId != existingAssetId) ||
                  ((nextCoverPath ?? '').trim() != existingCoverPath)
              ? existing.copyWith(
                  localAssetId: trimmedAssetId.isNotEmpty
                      ? trimmedAssetId
                      : existing.localAssetId,
                  localCoverPath: (nextCoverPath ?? '').trim().isNotEmpty
                      ? nextCoverPath
                      : existing.localCoverPath,
                )
              : existing;
          scannedSongs.add(nextSong);
          processed += 1;
          reportProgress();
          continue;
        }

        final tagInfo = settings.readFullTagsOnScan
            ? await _tagProbe.probeSongDedup(
                uri: candidate.path,
                isLocal: true,
                includeArtwork: settings.cacheArtwork,
              )
            : await _tagProbe.probeLocalBasicTags(uri: candidate.path);
        final title =
            _firstNonEmpty(
              tagInfo?.title,
              candidate.titleHint,
              p.basenameWithoutExtension(candidate.path),
            ) ??
            '未知标题';
        final artist = _firstNonEmpty(tagInfo?.artist, '未知艺术家') ?? '未知艺术家';
        final albumName =
            _firstNonEmpty(tagInfo?.album, candidate.albumHint, '未知专辑') ??
            '未知专辑';
        final durationMs = tagInfo?.durationMs ?? candidate.durationMs;
        if (settings.minDurationMs > 0 &&
            durationMs != null &&
            durationMs < settings.minDurationMs) {
          processed += 1;
          reportProgress();
          continue;
        }
        final coverPath = await _resolveCoverPath(
          file: file,
          fileModifiedMs: modifiedMs,
          assetId: candidate.assetId,
          artwork: settings.readFullTagsOnScan ? tagInfo?.artwork : null,
          existingCoverPath: existing?.localCoverPath,
          cacheArtworkEnabled: settings.cacheArtwork,
        );
        if (settings.readFullTagsOnScan) {
          final embeddedLyrics = tagInfo?.lyrics;
          if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
            await _lyricsRepo.saveLrcToCache(
              candidate.path,
              embeddedLyrics,
              overwrite: true,
            );
          }
        }
        scannedSongs.add(
          SongEntity(
            id: candidate.path,
            title: title,
            artist: artist,
            album: albumName.isNotEmpty ? albumName : null,
            uri: candidate.path,
            isLocal: true,
            durationMs: durationMs != null && durationMs > 0
                ? durationMs
                : null,
            bitrate: tagInfo?.bitrate ?? existing?.bitrate,
            sampleRate: tagInfo?.sampleRate ?? existing?.sampleRate,
            fileSize: tagInfo?.fileSize ?? stat.size,
            format: tagInfo?.format,
            sourceId: 'local',
            fileModifiedMs: modifiedMs,
            localCoverPath: coverPath,
            localAssetId: candidate.assetId,
            tagsParsed: tagInfo != null,
            trackNumber: tagInfo?.trackNumber ?? existing?.trackNumber,
            discNumber: tagInfo?.discNumber ?? existing?.discNumber,
          ),
        );
        processed += 1;
        if (!existingIds.contains(candidate.path)) {
          added += 1;
        }
        reportProgress();
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);

    reportProgress(force: true);
    final inserted = await _songDao.upsertSongs(scannedSongs);
    if (kDebugMode) {
      debugPrint('Local scan finished: $processed processed, $inserted added.');
    }
    return ScanResult(processed: processed, added: inserted);
  }

  Future<String?> _cacheArtwork({
    required File file,
    required int fileModifiedMs,
    required Uint8List? artwork,
    required bool enabled,
  }) async {
    if (!enabled) return null;
    if (artwork == null || artwork.isEmpty) return null;
    return ArtworkCacheHelper.cacheCompressedArtwork(
      bytes: artwork,
      key: '${file.path}_$fileModifiedMs',
    );
  }

  Future<String?> _resolveCoverPath({
    required File file,
    required int fileModifiedMs,
    required String? assetId,
    required Uint8List? artwork,
    required String? existingCoverPath,
    required bool cacheArtworkEnabled,
  }) async {
    final existingPath = (existingCoverPath ?? '').trim();
    if (existingPath.isNotEmpty) {
      final existingFile = File(existingPath);
      if (await existingFile.exists()) {
        return existingPath;
      }
    }

    final trimmedAssetId = (assetId ?? '').trim();
    if (trimmedAssetId.isNotEmpty) {
      final cached = await _cacheAssetThumbnail(
        assetId: trimmedAssetId,
        fileModifiedMs: fileModifiedMs,
      );
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    return _cacheArtwork(
      file: file,
      fileModifiedMs: fileModifiedMs,
      artwork: artwork,
      enabled: cacheArtworkEnabled,
    );
  }

  Future<String?> _cacheAssetThumbnail({
    required String assetId,
    required int fileModifiedMs,
  }) async {
    try {
      final entity = await AssetEntity.fromId(assetId);
      if (entity == null) return null;
      final bytes = await entity.thumbnailDataWithSize(
        const ThumbnailSize(320, 320),
      );
      if (bytes == null || bytes.isEmpty) return null;
      return ArtworkCacheHelper.cacheCompressedArtwork(
        bytes: bytes,
        key: 'asset:$assetId:$fileModifiedMs',
        quality: 86,
        minSize: 320,
      );
    } catch (_) {
      return null;
    }
  }

  String? _firstNonEmpty(String? a, [String? b, String? c]) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b != null && b.trim().isNotEmpty) return b.trim();
    if (c != null && c.trim().isNotEmpty) return c.trim();
    return null;
  }

  Future<List<File>> _collectCustomFiles(
    List<String> includePaths,
    ValueGetter<bool> isCancelled,
  ) async {
    if (includePaths.isEmpty) return [];
    final files = <File>[];
    final seen = <String>{};
    const extensions = {
      '.mp3',
      '.flac',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.alac',
      '.wma',
    };
    for (final path in includePaths) {
      if (isCancelled()) break;
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (isCancelled()) break;
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (!extensions.contains(ext)) continue;
          if (seen.add(entity.path)) {
            files.add(entity);
          }
        }
      }
    }
    return files;
  }
}
