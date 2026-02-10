import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WebDavSource {
  final String id;
  final String name;
  final String endpoint;
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
    required this.username,
    required this.password,
    required this.path,
    this.includeFolders = const [],
    this.excludeFolders = const [],
    this.scrapeTagsOnScan = false,
  });

  WebDavSource copyWith({
    String? id,
    String? name,
    String? endpoint,
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
        return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
      return const [];
    }

    return WebDavSource(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'WebDAV').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      path: (json['path'] ?? '/').toString(),
      includeFolders: readList('includeFolders'),
      excludeFolders: readList('excludeFolders'),
      scrapeTagsOnScan: json['scrapeTagsOnScan'] == true,
    );
  }
}

class WebDavSourceRepository {
  static final WebDavSourceRepository instance = WebDavSourceRepository._internal();
  WebDavSourceRepository._internal();

  static const String _prefsKey = 'webdav_sources_v1';

  Future<List<WebDavSource>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .whereType<Map>()
            .map((e) => WebDavSource.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.id.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<void> saveSources(List<WebDavSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(sources.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, data);
  }

  Future<void> upsert(WebDavSource source) async {
    final list = await loadSources();
    final idx = list.indexWhere((e) => e.id == source.id);
    final next = [...list];
    if (idx >= 0) {
      next[idx] = source;
    } else {
      next.add(source);
    }
    await saveSources(next);
  }

  Future<void> removeById(String id) async {
    final list = await loadSources();
    final next = list.where((e) => e.id != id).toList();
    await saveSources(next);
  }

  String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'webdav-$ts';
  }

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
