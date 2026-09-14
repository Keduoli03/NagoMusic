import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudDriveCredentials {
  final String appSecret;
  final String accessToken;
  final String refreshToken;
  final int expiresAtMs;
  final String cookie;

  const CloudDriveCredentials({
    this.appSecret = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.expiresAtMs = 0,
    this.cookie = '',
  });

  bool get hasBaiduSession => accessToken.isNotEmpty || refreshToken.isNotEmpty;
  bool get hasQuarkSession => cookie.isNotEmpty;

  CloudDriveCredentials copyWith({
    String? appSecret,
    String? accessToken,
    String? refreshToken,
    int? expiresAtMs,
    String? cookie,
  }) {
    return CloudDriveCredentials(
      appSecret: appSecret ?? this.appSecret,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      cookie: cookie ?? this.cookie,
    );
  }

  Map<String, dynamic> toJson() => {
    'appSecret': appSecret,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAtMs': expiresAtMs,
    'cookie': cookie,
  };

  factory CloudDriveCredentials.fromJson(Map<String, dynamic> json) {
    final rawExpiry = json['expiresAtMs'];
    return CloudDriveCredentials(
      appSecret: (json['appSecret'] ?? '').toString(),
      accessToken: (json['accessToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      expiresAtMs: rawExpiry is int
          ? rawExpiry
          : int.tryParse(rawExpiry?.toString() ?? '') ?? 0,
      cookie: (json['cookie'] ?? '').toString(),
    );
  }
}

abstract interface class CloudDriveCredentialStore {
  Future<CloudDriveCredentials> read(String sourceId);
  Future<void> write(String sourceId, CloudDriveCredentials credentials);
  Future<void> delete(String sourceId);
}

class SecureCloudDriveCredentialStore implements CloudDriveCredentialStore {
  static final SecureCloudDriveCredentialStore instance =
      SecureCloudDriveCredentialStore._internal();

  SecureCloudDriveCredentialStore._internal();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'cloud_drive_credentials_v1_';

  String _key(String sourceId) => '$_keyPrefix$sourceId';

  @override
  Future<CloudDriveCredentials> read(String sourceId) async {
    final raw = await _storage.read(key: _key(sourceId));
    if (raw == null || raw.trim().isEmpty) {
      return const CloudDriveCredentials();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CloudDriveCredentials.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return const CloudDriveCredentials();
  }

  @override
  Future<void> write(String sourceId, CloudDriveCredentials credentials) {
    return _storage.write(
      key: _key(sourceId),
      value: jsonEncode(credentials.toJson()),
    );
  }

  @override
  Future<void> delete(String sourceId) => _storage.delete(key: _key(sourceId));
}
