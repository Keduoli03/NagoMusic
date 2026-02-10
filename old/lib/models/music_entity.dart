import 'dart:typed_data';

class MusicEntity {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? uri;
  final bool isLocal;
  final int? durationMs;
  final Uint8List? artwork;
  final Map<String, String>? headers;
  final String? sourceId;
  final String? localCoverPath;
  final String? localLyricPath;
  final String? lyrics;
  final int? fileModifiedMs;
  final bool tagsParsed;
  final int? fileSize;
  final int? bitrate;
  final int? sampleRate;
  final String? format;

  const MusicEntity({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.uri,
    required this.isLocal,
    this.durationMs,
    this.artwork,
    this.headers,
    this.sourceId,
    this.localCoverPath,
    this.localLyricPath,
    this.lyrics,
    this.fileModifiedMs,
    this.tagsParsed = false,
    this.fileSize,
    this.bitrate,
    this.sampleRate,
    this.format,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'uri': uri,
      'isLocal': isLocal,
      'durationMs': durationMs,
      'headers': headers,
      'sourceId': sourceId,
      'localCoverPath': localCoverPath,
      'localLyricPath': localLyricPath,
      'lyrics': lyrics,
      'fileModifiedMs': fileModifiedMs,
      'tagsParsed': tagsParsed ? 1 : 0,
      'fileSize': fileSize,
      'bitrate': bitrate,
      'sampleRate': sampleRate,
      'format': format,
    };
  }

  factory MusicEntity.fromJson(Map<String, dynamic> json) {
    final headersRaw = json['headers'];
    Map<String, String>? headers;
    if (headersRaw is Map) {
      headers = headersRaw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    final tagsParsedRaw = json['tagsParsed'];
    final tagsParsed = tagsParsedRaw == 1 || tagsParsedRaw == true;
    return MusicEntity(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '未知标题').toString(),
      artist: (json['artist'] ?? '未知艺术家').toString(),
      album: json['album']?.toString(),
      uri: json['uri']?.toString(),
      isLocal: json['isLocal'] == true || json['isLocal'] == 1, // Handle SQLite int boolean
      durationMs: json['durationMs'] is int
          ? json['durationMs'] as int
          : int.tryParse(json['durationMs']?.toString() ?? ''),
      headers: headers,
      sourceId: json['sourceId']?.toString(),
      localCoverPath: json['localCoverPath']?.toString(),
      localLyricPath: json['localLyricPath']?.toString(),
      lyrics: json['lyrics']?.toString(),
      fileModifiedMs: json['fileModifiedMs'] is int
          ? json['fileModifiedMs'] as int
          : int.tryParse(json['fileModifiedMs']?.toString() ?? ''),
      tagsParsed: tagsParsed,
      fileSize: json['fileSize'] is int
          ? json['fileSize'] as int
          : int.tryParse(json['fileSize']?.toString() ?? ''),
      bitrate: json['bitrate'] is int
          ? json['bitrate'] as int
          : int.tryParse(json['bitrate']?.toString() ?? ''),
      sampleRate: json['sampleRate'] is int
          ? json['sampleRate'] as int
          : int.tryParse(json['sampleRate']?.toString() ?? ''),
      format: json['format']?.toString(),
    );
  }

  MusicEntity copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? uri,
    bool? isLocal,
    int? durationMs,
    Uint8List? artwork,
    Map<String, String>? headers,
    String? sourceId,
    String? localCoverPath,
    String? localLyricPath,
    String? lyrics,
    int? fileModifiedMs,
    bool? tagsParsed,
    int? fileSize,
    int? bitrate,
    int? sampleRate,
    String? format,
  }) {
    return MusicEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      uri: uri ?? this.uri,
      isLocal: isLocal ?? this.isLocal,
      durationMs: durationMs ?? this.durationMs,
      artwork: artwork ?? this.artwork,
      headers: headers ?? this.headers,
      sourceId: sourceId ?? this.sourceId,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      localLyricPath: localLyricPath ?? this.localLyricPath,
      lyrics: lyrics ?? this.lyrics,
      fileModifiedMs: fileModifiedMs ?? this.fileModifiedMs,
      tagsParsed: tagsParsed ?? this.tagsParsed,
      fileSize: fileSize ?? this.fileSize,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      format: format ?? this.format,
    );
  }
}

enum MusicSourceType { local, webdav }

class MusicSource {
  final String id;
  final MusicSourceType type;
  final String name;
  final String? endpoint;
  final String? username;
  final String? password;
  final String? path;
  final List<String> includeFolders;
  final List<String> excludeFolders;
  final int? minDurationMs;
  final bool useSystemLibrary;

  const MusicSource({
    required this.id,
    required this.type,
    required this.name,
    this.endpoint,
    this.username,
    this.password,
    this.path,
    this.includeFolders = const [],
    this.excludeFolders = const [],
    this.minDurationMs,
    this.useSystemLibrary = false,
  });

  MusicSource copyWith({
    String? id,
    MusicSourceType? type,
    String? name,
    String? endpoint,
    String? username,
    String? password,
    String? path,
    List<String>? includeFolders,
    List<String>? excludeFolders,
    int? minDurationMs,
    bool? useSystemLibrary,
  }) {
    return MusicSource(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      includeFolders: includeFolders ?? this.includeFolders,
      excludeFolders: excludeFolders ?? this.excludeFolders,
      minDurationMs: minDurationMs ?? this.minDurationMs,
      useSystemLibrary: useSystemLibrary ?? this.useSystemLibrary,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'endpoint': endpoint,
      'username': username,
      'password': password,
      'path': path,
      'includeFolders': includeFolders,
      'excludeFolders': excludeFolders,
      'minDurationMs': minDurationMs,
      'useSystemLibrary': useSystemLibrary,
    };
  }

  factory MusicSource.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'local').toString();
    final type = MusicSourceType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => MusicSourceType.local,
    );
    final includeFolders = (json['includeFolders'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final excludeFolders = (json['excludeFolders'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    return MusicSource(
      id: (json['id'] ?? '').toString(),
      type: type,
      name: (json['name'] ?? '').toString(),
      endpoint: json['endpoint']?.toString(),
      username: json['username']?.toString(),
      password: json['password']?.toString(),
      path: json['path']?.toString(),
      includeFolders: includeFolders,
      excludeFolders: excludeFolders,
      minDurationMs: json['minDurationMs'] is int
          ? json['minDurationMs'] as int
          : int.tryParse(json['minDurationMs']?.toString() ?? ''),
      useSystemLibrary: json['useSystemLibrary'] == true,
    );
  }
}
