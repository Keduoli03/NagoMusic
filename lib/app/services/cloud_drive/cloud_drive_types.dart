import 'package:flutter/foundation.dart';

enum CloudDriveProvider { baidu, quark }

class CloudDriveEntry {
  final String id;
  final String name;
  final String parentId;
  final String path;
  final bool isDirectory;
  final int? size;
  final int? modifiedMs;
  final int? durationMs;

  const CloudDriveEntry({
    required this.id,
    required this.name,
    required this.parentId,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedMs,
    this.durationMs,
  });
}

class CloudDrivePlaybackLink {
  final Uri uri;
  final Map<String, String> headers;

  const CloudDrivePlaybackLink({required this.uri, required this.headers});
}

class CloudDriveLoginChallenge {
  final String id;
  final String qrValue;
  final bool qrValueIsImageUrl;
  final String verificationUrl;
  final String userCode;
  final Duration expiresIn;
  final Duration pollInterval;

  const CloudDriveLoginChallenge({
    required this.id,
    required this.qrValue,
    required this.qrValueIsImageUrl,
    this.verificationUrl = '',
    this.userCode = '',
    required this.expiresIn,
    required this.pollInterval,
  });
}

enum CloudDriveLoginStatus { pending, complete, expired, denied }

class CloudDriveException implements Exception {
  final String message;
  final int? code;
  final bool authenticationRequired;
  final Object? cause;

  const CloudDriveException(
    this.message, {
    this.code,
    this.authenticationRequired = false,
    this.cause,
  });

  @override
  String toString() => 'CloudDriveException: $message';
}

typedef ScanCancelled = bool Function();
typedef ScanProgressChanged = ValueChanged<({int processed, int total})>;
