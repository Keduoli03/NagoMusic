import '../../state/song_state.dart';
import '../db/dao/song_dao.dart';
import '../scan_types.dart';
import 'baidu/baidu_netdisk_client.dart';
import 'cloud_drive_source_repository.dart';
import 'cloud_drive_types.dart';
import 'quark/quark_netdisk_client.dart';

class CloudDriveMusicService {
  CloudDriveMusicService({
    BaiduNetdiskClient? baiduClient,
    QuarkNetdiskClient? quarkClient,
    CloudDriveSourceRepository? sourceRepository,
    SongDao? songDao,
  }) : _baidu = baiduClient ?? BaiduNetdiskClient(),
       _quark = quarkClient ?? QuarkNetdiskClient(),
       _sources = sourceRepository ?? CloudDriveSourceRepository.instance,
       _songDao = songDao ?? SongDao();

  static final CloudDriveMusicService instance = CloudDriveMusicService();

  static const Set<String> _audioExtensions = {
    'mp3',
    'flac',
    'wav',
    'm4a',
    'ogg',
    'aac',
    'opus',
  };

  final BaiduNetdiskClient _baidu;
  final QuarkNetdiskClient _quark;
  final CloudDriveSourceRepository _sources;
  final SongDao _songDao;

  static bool isCloudDriveSong(SongEntity song) {
    final sourceId = song.sourceId ?? '';
    final uri = song.uri ?? '';
    return sourceId.startsWith('baidu-') ||
        sourceId.startsWith('quark-') ||
        uri.startsWith('baidu://') ||
        uri.startsWith('quark://');
  }

  static String placeholderUri(CloudDriveProvider provider, String fileId) {
    return '${provider.name}://file/${Uri.encodeComponent(fileId)}';
  }

  static String fileIdFromUri(String rawUri) {
    final uri = Uri.parse(rawUri);
    if (uri.pathSegments.isEmpty) {
      throw const CloudDriveException('网盘歌曲缺少文件标识');
    }
    return uri.pathSegments.first;
  }

  Future<bool> isAuthenticated(CloudDriveSource source) =>
      switch (source.provider) {
        CloudDriveProvider.baidu => _baidu.isAuthenticated(source.id),
        CloudDriveProvider.quark => _quark.isAuthenticated(source.id),
      };

  Future<void> logout(CloudDriveSource source) => switch (source.provider) {
    CloudDriveProvider.baidu => _baidu.logout(source.id),
    CloudDriveProvider.quark => _quark.logout(source.id),
  };

  Future<CloudDriveLoginChallenge> beginLogin(
    CloudDriveSource source, {
    String baiduAppSecret = '',
  }) => switch (source.provider) {
    CloudDriveProvider.baidu => _baidu.beginLogin(
      source,
      appSecret: baiduAppSecret,
    ),
    CloudDriveProvider.quark => _quark.beginLogin(source),
  };

  Future<CloudDriveLoginStatus> pollLogin(
    CloudDriveSource source,
    CloudDriveLoginChallenge challenge,
  ) => switch (source.provider) {
    CloudDriveProvider.baidu => _baidu.pollLogin(source, challenge),
    CloudDriveProvider.quark => _quark.pollLogin(source, challenge),
  };

  Future<List<CloudDriveEntry>> listChildren(
    CloudDriveSource source,
    String parentId,
  ) => switch (source.provider) {
    CloudDriveProvider.baidu => _baidu.listChildren(source, parentId),
    CloudDriveProvider.quark => _quark.listChildren(source, parentId),
  };

  Future<bool> testConnection(CloudDriveSource source) =>
      switch (source.provider) {
        CloudDriveProvider.baidu => _baidu.testConnection(source),
        CloudDriveProvider.quark => _quark.testConnection(source),
      };

  Future<Map<String, String>> playbackHeaders(SongEntity song) async {
    final source = await _sourceForSong(song);
    return switch (source.provider) {
      CloudDriveProvider.baidu => _baidu.playbackHeaders(source),
      CloudDriveProvider.quark => _quark.playbackHeaders(source),
    };
  }

  Future<Uri?> resolvePlaybackUri(
    SongEntity song, {
    bool forceRefresh = false,
  }) async {
    final source = await _sourceForSong(song);
    final fileId = fileIdFromUri(song.uri ?? '');
    final link = switch (source.provider) {
      CloudDriveProvider.baidu => _baidu.resolvePlaybackLink(
        source,
        fileId,
        forceRefresh: forceRefresh,
      ),
      CloudDriveProvider.quark => _quark.resolvePlaybackLink(
        source,
        fileId,
        forceRefresh: forceRefresh,
      ),
    };
    return (await link).uri;
  }

  Future<ScanResult> scan({
    required CloudDriveSource source,
    required bool Function() isCancelled,
    required void Function(ScanProgress progress) onProgress,
  }) async {
    final existing = await _songDao.fetchAll(sourceId: source.id);
    final existingById = {for (final song in existing) song.id: song};
    final songs = <SongEntity>[];
    var processedFiles = 0;
    final queue = <_CloudDirectory>[
      _CloudDirectory(
        id: source.root,
        displayPath: source.provider == CloudDriveProvider.baidu
            ? _normalizeDisplayPath(source.root)
            : '/',
      ),
    ];
    var directoryIndex = 0;

    onProgress(const ScanProgress(processed: 0, added: 0, total: 0));
    while (directoryIndex < queue.length && !isCancelled()) {
      final directory = queue[directoryIndex++];
      final entries = await listChildren(source, directory.id);
      for (final entry in entries) {
        if (isCancelled()) break;
        final displayPath = source.provider == CloudDriveProvider.baidu
            ? _normalizeDisplayPath(entry.path)
            : _joinDisplayPath(directory.displayPath, entry.name);
        if (entry.isDirectory) {
          if (entry.id.isNotEmpty) {
            queue.add(_CloudDirectory(id: entry.id, displayPath: displayPath));
          }
          continue;
        }
        processedFiles += 1;
        final extension = _extension(entry.name);
        if (_audioExtensions.contains(extension) && entry.id.isNotEmpty) {
          final id = '${source.id}:${entry.id}';
          final base = SongEntity(
            id: id,
            title: _titleWithoutExtension(entry.name),
            artist: source.name.trim().isEmpty
                ? source.provider.displayName
                : source.name.trim(),
            album: _parentName(displayPath),
            uri: placeholderUri(source.provider, entry.id),
            isLocal: false,
            durationMs: entry.durationMs,
            fileSize: entry.size,
            format: extension,
            sourceId: source.id,
            fileModifiedMs: entry.modifiedMs,
          );
          songs.add(_preserveMetadata(base, existingById[id]));
        }
        onProgress(
          ScanProgress(
            processed: processedFiles,
            added: 0,
            total: processedFiles + queue.length - directoryIndex,
          ),
        );
      }
    }

    if (isCancelled()) {
      return ScanResult(processed: processedFiles, added: 0);
    }
    final existingIds = existingById.keys.toSet();
    final added = songs.where((song) => !existingIds.contains(song.id)).length;
    await _songDao.deleteBySource(source.id);
    await _songDao.upsertSongs(songs);
    onProgress(
      ScanProgress(
        processed: processedFiles,
        added: added,
        total: processedFiles,
      ),
    );
    return ScanResult(processed: processedFiles, added: added);
  }

  Future<CloudDriveSource> _sourceForSong(SongEntity song) async {
    final sourceId = song.sourceId ?? '';
    final source = await _sources.findById(sourceId);
    if (source == null) {
      throw const CloudDriveException('找不到这首歌对应的网盘来源');
    }
    return source;
  }

  SongEntity _preserveMetadata(SongEntity base, SongEntity? existing) {
    if (existing == null || !existing.tagsParsed) return base;
    return existing.copyWith(
      uri: base.uri,
      durationMs: base.durationMs,
      fileSize: base.fileSize,
      format: base.format,
      sourceId: base.sourceId,
      fileModifiedMs: base.fileModifiedMs,
    );
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _titleWithoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _normalizeDisplayPath(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '/';
    if (!value.startsWith('/')) value = '/$value';
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _joinDisplayPath(String parent, String name) {
    final normalized = _normalizeDisplayPath(parent);
    return normalized == '/' ? '/$name' : '$normalized/$name';
  }

  static String? _parentName(String path) {
    final segments = _normalizeDisplayPath(
      path,
    ).split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2) return null;
    return segments[segments.length - 2];
  }
}

class _CloudDirectory {
  final String id;
  final String displayPath;

  const _CloudDirectory({required this.id, required this.displayPath});
}
