import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../prefs_source_repository.dart';

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

class NavidromeSourceRepository extends PrefsSourceRepository<NavidromeSource> {
  static final NavidromeSourceRepository instance =
      NavidromeSourceRepository._internal();

  NavidromeSourceRepository._internal();

  static const String apiVersion = '1.16.1';
  static const String clientName = 'nagomusic';

  @override
  String get prefsKey => 'navidrome_sources_v1';

  @override
  String get idPrefix => 'navidrome';

  @override
  NavidromeSource fromJson(Map<String, dynamic> json) =>
      NavidromeSource.fromJson(json);

  @override
  Map<String, dynamic> toJson(NavidromeSource source) => source.toJson();

  @override
  String idOf(NavidromeSource source) => source.id;

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
