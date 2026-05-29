import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NavidromeSource {
  final String id;
  final String name;
  final String endpoint;
  final String username;
  final String password;
  final String salt;

  const NavidromeSource({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.username,
    required this.password,
    required this.salt,
  });

  NavidromeSource copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? username,
    String? password,
    String? salt,
  }) {
    return NavidromeSource(
      id: id ?? this.id,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      username: username ?? this.username,
      password: password ?? this.password,
      salt: salt ?? this.salt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'endpoint': endpoint,
      'username': username,
      'password': password,
      'salt': salt,
    };
  }

  factory NavidromeSource.fromJson(Map<String, dynamic> json) {
    return NavidromeSource(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Navidrome').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      salt: (json['salt'] ?? '').toString(),
    );
  }
}

class NavidromeSourceRepository {
  static final NavidromeSourceRepository instance =
      NavidromeSourceRepository._internal();

  NavidromeSourceRepository._internal();

  static const String _prefsKey = 'navidrome_sources_v1';
  static const String apiVersion = '1.16.1';
  static const String clientName = 'nagomusic';

  Future<List<NavidromeSource>> loadSources() async {
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
            .map((e) => NavidromeSource.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.id.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<void> saveSources(List<NavidromeSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(sources.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, data);
  }

  Future<void> upsert(NavidromeSource source) async {
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
    return 'navidrome-$ts';
  }

  String newSalt() {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    return List.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Uri apiUri(
    NavidromeSource source,
    String method, {
    Map<String, String> query = const {},
  }) {
    final endpoint = _normalizeEndpoint(source.endpoint);
    final token = md5
        .convert(utf8.encode('${source.password}${source.salt}'))
        .toString();
    return endpoint.replace(
      path: _joinPath(endpoint.path, 'rest/$method.view'),
      queryParameters: {
        'u': source.username,
        't': token,
        's': source.salt,
        'v': apiVersion,
        'c': clientName,
        'f': 'json',
        ...query,
      },
    );
  }

  Uri _normalizeEndpoint(String raw) {
    final text = raw.trim();
    final withScheme = text.startsWith('http://') || text.startsWith('https://')
        ? text
        : 'https://$text';
    final uri = Uri.parse(withScheme);
    final path = _trimTrailingSlash(uri.path);
    final normalizedPath = path.toLowerCase().endsWith('/rest')
        ? path.substring(0, path.length - 5)
        : path;
    return uri.replace(path: normalizedPath);
  }

  String _joinPath(String base, String child) {
    final normalized = _trimTrailingSlash(base);
    if (normalized.isEmpty || normalized == '/') return '/$child';
    return '$normalized/$child';
  }

  String _trimTrailingSlash(String value) {
    var text = value.trim();
    while (text.length > 1 && text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}
