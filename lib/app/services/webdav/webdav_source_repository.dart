import 'dart:convert';

import '../prefs_source_repository.dart';

class WebDavSource {
  final String id;
  final String name;
  final String endpoint;
  // Alternate addresses for the same server (e.g. LAN address at home vs. a
  // reverse-tunnel/DDNS address while away). Scanning and playback try
  // [endpoint] first, then these in order, and cache whichever answers.
  final List<String> altEndpoints;
  final String username;
  final String password;
  final String path;
  final List<String> includeFolders;
  final List<String> excludeFolders;
  final bool scrapeTagsOnScan;

  const WebDavSource({
    required this.id,
    required this.name,
    required this.endpoint,
    this.altEndpoints = const [],
    required this.username,
    required this.password,
    required this.path,
    this.includeFolders = const [],
    this.excludeFolders = const [],
    this.scrapeTagsOnScan = false,
  });

  /// [endpoint] followed by [altEndpoints], trimmed and de-duplicated.
  List<String> get allEndpoints {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in [endpoint, ...altEndpoints]) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) result.add(t);
    }
    return result;
  }

  WebDavSource copyWith({
    String? id,
    String? name,
    String? endpoint,
    List<String>? altEndpoints,
    String? username,
    String? password,
    String? path,
    List<String>? includeFolders,
    List<String>? excludeFolders,
    bool? scrapeTagsOnScan,
  }) {
    return WebDavSource(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      altEndpoints: altEndpoints ?? this.altEndpoints,
      username: username ?? this.username,
      password: password ?? this.password,
      path: path ?? this.path,
      includeFolders: includeFolders ?? this.includeFolders,
      excludeFolders: excludeFolders ?? this.excludeFolders,
      scrapeTagsOnScan: scrapeTagsOnScan ?? this.scrapeTagsOnScan,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'altEndpoints': altEndpoints,
      'username': username,
      'password': password,
      'path': path,
      'includeFolders': includeFolders,
      'excludeFolders': excludeFolders,
      'scrapeTagsOnScan': scrapeTagsOnScan,
    };
  }

  factory WebDavSource.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      final raw = json[key];
      if (raw is List) {
        return raw
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
      return const [];
    }

    return WebDavSource(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'WebDAV').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      altEndpoints: readList('altEndpoints'),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      path: (json['path'] ?? '/').toString(),
      includeFolders: readList('includeFolders'),
      excludeFolders: readList('excludeFolders'),
      scrapeTagsOnScan: json['scrapeTagsOnScan'] == true,
    );
  }
}

class WebDavSourceRepository extends PrefsSourceRepository<WebDavSource> {
  static final WebDavSourceRepository instance =
      WebDavSourceRepository._internal();
  WebDavSourceRepository._internal();

  @override
  String get prefsKey => 'webdav_sources_v1';

  @override
  String get idPrefix => 'webdav';

  @override
  WebDavSource fromJson(Map<String, dynamic> json) =>
      WebDavSource.fromJson(json);

  @override
  Map<String, dynamic> toJson(WebDavSource source) => source.toJson();

  @override
  String idOf(WebDavSource source) => source.id;

  Map<String, String> buildHeaders(WebDavSource source) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };
    final u = source.username.trim();
    final p = source.password;
    if (u.isNotEmpty || p.isNotEmpty) {
      final auth = base64Encode(utf8.encode('$u:$p'));
      headers['Authorization'] = 'Basic $auth';
    }
    return headers;
  }
}
