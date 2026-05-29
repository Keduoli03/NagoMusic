import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../state/settings_state.dart';
import 'db/dao/song_dao.dart';
import 'local_music_service.dart';
import 'navidrome/navidrome_music_service.dart';
import 'navidrome/navidrome_source_repository.dart';
import 'webdav/webdav_music_service.dart';
import 'webdav/webdav_source_repository.dart';

class LibraryRefreshResult {
  final int localAdded;
  final int cloudAdded;

  const LibraryRefreshResult({
    required this.localAdded,
    required this.cloudAdded,
  });

  bool get hasChanges => localAdded > 0 || cloudAdded > 0;
}

class LibraryRefreshService {
  LibraryRefreshService._();

  static final LibraryRefreshService instance = LibraryRefreshService._();

  final LocalMusicService _localService = LocalMusicService();
  final WebDavMusicService _webDavService = WebDavMusicService();
  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final NavidromeMusicService _navidromeService = NavidromeMusicService();
  final NavidromeSourceRepository _navidromeRepo =
      NavidromeSourceRepository.instance;
  final SongDao _songDao = SongDao();

  bool _running = false;

  Future<LibraryRefreshResult?> refreshOnLaunch() async {
    if (_running) return null;
    _running = true;
    try {
      await LibraryRefreshSettings.ensureLoaded();

      var localAdded = 0;
      var cloudAdded = 0;

      if (LibraryRefreshSettings.autoRefreshLocalOnLaunch.value) {
        localAdded = await _refreshLocalSilently();
      }

      if (LibraryRefreshSettings.autoRefreshCloudOnLaunch.value) {
        cloudAdded = await _refreshCloudSilently();
      }

      return LibraryRefreshResult(
        localAdded: localAdded,
        cloudAdded: cloudAdded,
      );
    } finally {
      _running = false;
    }
  }

  Future<int> _refreshLocalSilently() async {
    try {
      final permission = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.audio,
            mediaLocation: false,
          ),
        ),
      );
      if (!permission.isAuth) {
        return 0;
      }

      final settings = await _localService.loadSettings();
      final result = await _localService.scan(
        settings: settings,
        isCancelled: () => false,
        onProgress: (_) {},
      );
      await _localService.saveLastScanCount(result.added);
      return result.added;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Silent local refresh failed: $e');
      }
      return 0;
    }
  }

  Future<int> _refreshCloudSilently() async {
    try {
      final sources = await _webDavRepo.loadSources();
      if (sources.isEmpty) return 0;

      var added = 0;
      for (final source in sources) {
        if (source.endpoint.trim().isEmpty) continue;
        final result = await _webDavService.scan(
          source: source,
          isCancelled: () => false,
          onProgress: (_) {},
        );
        added += result.added;
      }
      final navidromeSources = await _navidromeRepo.loadSources();
      for (final source in navidromeSources) {
        if (source.endpoint.trim().isEmpty) continue;
        final result = await _navidromeService.scan(
          source: source,
          isCancelled: () => false,
          onProgress: (_) {},
        );
        added += result.added;
      }
      return added;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Silent cloud refresh failed: $e');
      }
      return 0;
    }
  }

  Future<int> getLocalSongCount() {
    return _localService.getLocalSongCount();
  }

  Future<Map<String, int>> getCloudSongCounts() async {
    final webDavSources = await _webDavRepo.loadSources();
    final navidromeSources = await _navidromeRepo.loadSources();
    final entries = await Future.wait([
      ...webDavSources.map(
        (s) async =>
            MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
      ),
      ...navidromeSources.map(
        (s) async =>
            MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
      ),
    ]);
    return {for (final e in entries) e.key: e.value};
  }
}
