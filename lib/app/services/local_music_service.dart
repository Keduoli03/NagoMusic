import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/song_state.dart';
import 'artwork_cache_helper.dart';
import 'db/dao/song_dao.dart';
import 'lyrics/lyrics_repository.dart';
import 'metadata/tag_probe_service.dart';

class LocalSourceSettings {
  final bool useSystemLibrary;
  final int minDurationMs;
  final List<String> includeAlbumIds;
  final List<String> includePaths;
  final int lastScanCount;
  final bool cacheArtwork;

  const LocalSourceSettings({
    required this.useSystemLibrary,
    required this.minDurationMs,
    required this.includeAlbumIds,
    required this.includePaths,
    required this.lastScanCount,
    required this.cacheArtwork,
  });

  factory LocalSourceSettings.defaults() {
    return const LocalSourceSettings(
      useSystemLibrary: true,
      minDurationMs: 0,
      includeAlbumIds: [],
      includePaths: [],
      lastScanCount: 0,
      cacheArtwork: false,
    );
  }

  LocalSourceSettings copyWith({
    bool? useSystemLibrary,
    int? minDurationMs,
    List<String>? includeAlbumIds,
    List<String>? includePaths,
    int? lastScanCount,
    bool? cacheArtwork,
  }) {
    return LocalSourceSettings(
      useSystemLibrary: useSystemLibrary ?? this.useSystemLibrary,
      minDurationMs: minDurationMs ?? this.minDurationMs,
      includeAlbumIds: includeAlbumIds ?? this.includeAlbumIds,
      includePaths: includePaths ?? this.includePaths,
      lastScanCount: lastScanCount ?? this.lastScanCount,
      cacheArtwork: cacheArtwork ?? this.cacheArtwork,
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
    );
  }
}

class LocalScanProgress {
  final int processed;
  final int added;
  final int total;

  const LocalScanProgress({
    required this.processed,
    required this.added,
    required this.total,
  });
}

class LocalScanResult {
  final int processed;
  final int added;

  const LocalScanResult({
    required this.processed,
    required this.added,
  });
}

class LocalMusicService {
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
    } catch (_) {
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
      orders: [
        const OrderOption(type: OrderOptionType.updateDate, asc: false),
      ],
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

  Future<LocalScanResult> scan({
    required LocalSourceSettings settings,
    required ValueGetter<bool> isCancelled,
    required ValueChanged<LocalScanProgress> onProgress,
  }) async {
    var processed = 0;
    var added = 0;
    final scannedSongs = <SongEntity>[];
    final existingIds = await _songDao.fetchIdsBySource('local');
    final seenPaths = <String>{};
    final customFiles = await _collectCustomFiles(
      settings.includePaths,
      isCancelled,
    );
    var total = customFiles.length;

    List<AssetPathEntity> selectedAlbums = [];
    final includeSet = settings.includeAlbumIds.toSet();
    final needAlbumScan =
        settings.useSystemLibrary || includeSet.isNotEmpty;
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

    final albumCounts = <String, int>{};
    for (final album in selectedAlbums) {
      final count = await album.assetCountAsync;
      albumCounts[album.id] = count;
      total += count;
    }

    for (final album in selectedAlbums) {
      if (isCancelled()) break;
      final count = albumCounts[album.id] ?? 0;
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
          final stat = await file.stat();
          final tagInfo = await _tagProbe.probeSongDedup(
            uri: file.path,
            isLocal: true,
            includeArtwork: settings.cacheArtwork,
          );
          final title = _firstNonEmpty(
                tagInfo?.title,
                entity.title,
                p.basenameWithoutExtension(file.path),
              ) ??
              '未知标题';
          final artist =
              _firstNonEmpty(tagInfo?.artist, '未知艺术家') ?? '未知艺术家';
          final albumName =
              _firstNonEmpty(tagInfo?.album, album.name) ?? album.name;
          final durationMs =
              tagInfo?.durationMs ?? (entity.duration * 1000).round();
          final coverPath = await _cacheArtwork(
            file: file,
            fileModifiedMs: stat.modified.millisecondsSinceEpoch,
            artwork: tagInfo?.artwork,
            enabled: settings.cacheArtwork,
          );
          final embeddedLyrics = tagInfo?.lyrics;
          if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
            await _lyricsRepo.saveLrcToCache(
              file.path,
              embeddedLyrics,
              overwrite: true,
            );
          }
          scannedSongs.add(
            SongEntity(
              id: file.path,
              title: title,
              artist: artist,
              album: albumName.isNotEmpty ? albumName : null,
              uri: file.path,
              isLocal: true,
              durationMs: durationMs > 0 ? durationMs : null,
              bitrate: tagInfo?.bitrate,
              sampleRate: tagInfo?.sampleRate,
              fileSize: tagInfo?.fileSize ?? stat.size,
              format: tagInfo?.format,
              sourceId: 'local',
              fileModifiedMs: stat.modified.millisecondsSinceEpoch,
              localCoverPath: coverPath,
              tagsParsed: tagInfo != null,
            ),
          );
          processed += 1;
          if (!existingIds.contains(file.path)) {
            added += 1;
          }
          if (processed % 20 == 0) {
            onProgress(
              LocalScanProgress(processed: processed, added: added, total: total),
            );
          }
        }
        start = end;
      }
    }

    for (final file in customFiles) {
      if (isCancelled()) break;
      if (!seenPaths.add(file.path)) {
        continue;
      }
      final stat = await file.stat();
      final tagInfo = await _tagProbe.probeSongDedup(
        uri: file.path,
        isLocal: true,
        includeArtwork: settings.cacheArtwork,
      );
      final title =
          _firstNonEmpty(tagInfo?.title, p.basenameWithoutExtension(file.path)) ??
              '未知标题';
      final albumName =
          _firstNonEmpty(tagInfo?.album, p.basename(p.dirname(file.path))) ??
              '';
      final artist =
          _firstNonEmpty(tagInfo?.artist, '未知艺术家') ?? '未知艺术家';
      final coverPath = await _cacheArtwork(
        file: file,
        fileModifiedMs: stat.modified.millisecondsSinceEpoch,
        artwork: tagInfo?.artwork,
        enabled: settings.cacheArtwork,
      );
      final embeddedLyrics = tagInfo?.lyrics;
      if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
        await _lyricsRepo.saveLrcToCache(
          file.path,
          embeddedLyrics,
          overwrite: true,
        );
      }
      scannedSongs.add(
        SongEntity(
          id: file.path,
          title: title,
          artist: artist,
          album: albumName.isNotEmpty ? albumName : null,
          uri: file.path,
          isLocal: true,
          durationMs: tagInfo?.durationMs,
          bitrate: tagInfo?.bitrate,
          sampleRate: tagInfo?.sampleRate,
          fileSize: tagInfo?.fileSize ?? stat.size,
          format: tagInfo?.format,
          sourceId: 'local',
          fileModifiedMs: stat.modified.millisecondsSinceEpoch,
          localCoverPath: coverPath,
          tagsParsed: tagInfo != null,
        ),
      );
      processed += 1;
      if (!existingIds.contains(file.path)) {
        added += 1;
      }
      if (processed % 20 == 0) {
        onProgress(
          LocalScanProgress(processed: processed, added: added, total: total),
        );
      }
    }

    onProgress(
      LocalScanProgress(processed: processed, added: added, total: total),
    );
    final inserted = await _songDao.upsertSongs(scannedSongs);
    if (kDebugMode) {
      debugPrint('Local scan finished: $processed processed, $inserted added.');
    }
    return LocalScanResult(processed: processed, added: inserted);
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
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
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
