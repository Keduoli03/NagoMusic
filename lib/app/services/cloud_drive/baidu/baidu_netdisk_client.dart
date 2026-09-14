import 'dart:async';

import 'package:dio/dio.dart';

import '../../log/log.dart';
import '../cloud_drive_credential_store.dart';
import '../cloud_drive_source_repository.dart';
import '../cloud_drive_types.dart';

class BaiduNetdiskClient {
  static const String _logTag = 'BaiduNetdiskClient';
  static const String _oauthBase = 'https://openapi.baidu.com';
  static const String _apiBase = 'https://pan.baidu.com/rest/2.0';
  static const String downloadUserAgent = 'pan.baidu.com';

  final Dio _dio;
  final CloudDriveCredentialStore _credentials;
  final Map<String, Future<String>> _refreshing = {};

  BaiduNetdiskClient({Dio? dio, CloudDriveCredentialStore? credentials})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _credentials = credentials ?? SecureCloudDriveCredentialStore.instance;

  Future<void> saveAppSecret(String sourceId, String appSecret) async {
    final current = await _credentials.read(sourceId);
    await _credentials.write(
      sourceId,
      current.copyWith(appSecret: appSecret.trim()),
    );
  }

  Future<bool> isAuthenticated(String sourceId) async {
    final credentials = await _credentials.read(sourceId);
    return credentials.hasBaiduSession;
  }

  Future<void> logout(String sourceId) => _credentials.delete(sourceId);

  Future<CloudDriveLoginChallenge> beginLogin(
    CloudDriveSource source, {
    required String appSecret,
  }) async {
    final appKey = source.appKey.trim();
    final currentCredentials = await _credentials.read(source.id);
    final secret = appSecret.trim().isEmpty
        ? currentCredentials.appSecret.trim()
        : appSecret.trim();
    if (appKey.isEmpty || secret.isEmpty) {
      throw const CloudDriveException('请先填写百度网盘 App Key 和 Secret Key');
    }
    await saveAppSecret(source.id, secret);

    final data = await _getJson(
      '$_oauthBase/oauth/2.0/device/code',
      query: {
        'response_type': 'device_code',
        'client_id': appKey,
        'scope': 'basic,netdisk',
      },
    );
    _throwOAuthError(data);
    final deviceCode = _string(data['device_code']);
    final qrUrl = _string(data['qrcode_url']);
    if (deviceCode.isEmpty || qrUrl.isEmpty) {
      throw const CloudDriveException('百度网盘未返回有效的登录二维码');
    }
    return CloudDriveLoginChallenge(
      id: deviceCode,
      qrValue: qrUrl,
      qrValueIsImageUrl: true,
      verificationUrl: _string(data['verification_url']),
      userCode: _string(data['user_code']),
      expiresIn: Duration(seconds: _int(data['expires_in']) ?? 300),
      pollInterval: Duration(seconds: _int(data['interval']) ?? 5),
    );
  }

  Future<CloudDriveLoginStatus> pollLogin(
    CloudDriveSource source,
    CloudDriveLoginChallenge challenge,
  ) async {
    final credentials = await _credentials.read(source.id);
    final secret = credentials.appSecret.trim();
    if (source.appKey.trim().isEmpty || secret.isEmpty) {
      throw const CloudDriveException('百度网盘应用密钥不完整');
    }

    final data = await _getJson(
      '$_oauthBase/oauth/2.0/token',
      query: {
        'grant_type': 'device_token',
        'code': challenge.id,
        'client_id': source.appKey.trim(),
        'client_secret': secret,
      },
    );
    final error = _string(data['error']);
    if (error == 'authorization_pending' || error == 'slow_down') {
      return CloudDriveLoginStatus.pending;
    }
    if (error == 'expired_token') return CloudDriveLoginStatus.expired;
    if (error == 'access_denied') return CloudDriveLoginStatus.denied;
    _throwOAuthError(data);

    final accessToken = _string(data['access_token']);
    if (accessToken.isEmpty) {
      throw const CloudDriveException('百度网盘授权成功，但没有返回 Access Token');
    }
    final expiresIn = _int(data['expires_in']) ?? 2592000;
    await _credentials.write(
      source.id,
      credentials.copyWith(
        accessToken: accessToken,
        refreshToken: _string(data['refresh_token']),
        expiresAtMs: DateTime.now()
            .add(Duration(seconds: expiresIn))
            .millisecondsSinceEpoch,
      ),
    );
    return CloudDriveLoginStatus.complete;
  }

  Future<List<CloudDriveEntry>> listChildren(
    CloudDriveSource source,
    String directory,
  ) async {
    final normalized = _normalizePath(directory);
    final result = <CloudDriveEntry>[];
    var start = 0;
    const limit = 1000;
    while (true) {
      final data = await _authorizedGet(
        source,
        '$_apiBase/xpan/file',
        query: {
          'method': 'list',
          'dir': normalized,
          'start': '$start',
          'limit': '$limit',
          'order': 'name',
          'desc': '0',
          'web': '1',
        },
      );
      final rawList = data['list'];
      final page = rawList is List
          ? rawList.whereType<Map>().map((raw) {
              final item = raw.cast<String, dynamic>();
              final path = _string(item['path']);
              final name = _string(item['server_filename']);
              return CloudDriveEntry(
                id: _string(item['fs_id']),
                name: name,
                parentId: normalized,
                path: path.isEmpty ? _joinPath(normalized, name) : path,
                isDirectory: _int(item['isdir']) == 1,
                size: _int(item['size']),
                modifiedMs: (_int(item['server_mtime']) ?? 0) * 1000,
              );
            }).toList()
          : const <CloudDriveEntry>[];
      result.addAll(page);
      if (page.length < limit) break;
      start += page.length;
    }
    return result;
  }

  Future<bool> testConnection(CloudDriveSource source) async {
    try {
      await listChildren(source, source.root);
      return true;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '测试百度网盘连接失败 sourceId=${source.id}', e, s);
      return false;
    }
  }

  Future<Map<String, String>> playbackHeaders(CloudDriveSource source) async {
    await _validAccessToken(source);
    return const {'User-Agent': downloadUserAgent, 'Accept': '*/*'};
  }

  Future<CloudDrivePlaybackLink> resolvePlaybackLink(
    CloudDriveSource source,
    String fileId, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      await _refreshAccessToken(source, force: true);
    }
    final token = await _validAccessToken(source);
    final data = await _authorizedGet(
      source,
      '$_apiBase/xpan/multimedia',
      query: {'method': 'filemetas', 'dlink': '1', 'fsids': '[$fileId]'},
    );
    final list = data['list'];
    if (list is! List || list.isEmpty || list.first is! Map) {
      throw const CloudDriveException('百度网盘没有返回文件下载地址');
    }
    final dlink = _string((list.first as Map)['dlink']);
    if (dlink.isEmpty) {
      throw const CloudDriveException('百度网盘文件暂时无法下载');
    }
    final rawUri = Uri.parse(dlink);
    final uri = rawUri.replace(
      queryParameters: {...rawUri.queryParameters, 'access_token': token},
    );
    return CloudDrivePlaybackLink(
      uri: uri,
      headers: const {'User-Agent': downloadUserAgent, 'Accept': '*/*'},
    );
  }

  Future<Map<String, dynamic>> _authorizedGet(
    CloudDriveSource source,
    String url, {
    required Map<String, String> query,
    bool retried = false,
  }) async {
    final token = await _validAccessToken(source);
    final data = await _getJson(url, query: {...query, 'access_token': token});
    final errno = _int(data['errno']) ?? _int(data['error_code']) ?? 0;
    if ((errno == -6 || errno == 111) && !retried) {
      await _refreshAccessToken(source, force: true);
      return _authorizedGet(source, url, query: query, retried: true);
    }
    if (errno != 0) {
      throw CloudDriveException(
        _string(data['errmsg']).isNotEmpty
            ? _string(data['errmsg'])
            : _string(data['error_msg']).isNotEmpty
            ? _string(data['error_msg'])
            : '百度网盘请求失败（$errno）',
        code: errno,
        authenticationRequired: errno == -6 || errno == 111,
      );
    }
    return data;
  }

  Future<String> _validAccessToken(CloudDriveSource source) async {
    final current = await _credentials.read(source.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (current.accessToken.isNotEmpty && current.expiresAtMs > now + 60000) {
      return current.accessToken;
    }
    if (current.refreshToken.isEmpty) {
      if (current.accessToken.isNotEmpty) return current.accessToken;
      throw const CloudDriveException('百度网盘尚未登录', authenticationRequired: true);
    }
    return _refreshAccessToken(source);
  }

  Future<String> _refreshAccessToken(
    CloudDriveSource source, {
    bool force = false,
  }) {
    final inflight = _refreshing[source.id];
    if (inflight != null) return inflight;
    final future = _doRefreshAccessToken(source, force: force);
    _refreshing[source.id] = future;
    future.whenComplete(() => _refreshing.remove(source.id));
    return future;
  }

  Future<String> _doRefreshAccessToken(
    CloudDriveSource source, {
    required bool force,
  }) async {
    final current = await _credentials.read(source.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        current.accessToken.isNotEmpty &&
        current.expiresAtMs > now + 60000) {
      return current.accessToken;
    }
    if (current.refreshToken.isEmpty || current.appSecret.isEmpty) {
      throw const CloudDriveException(
        '百度网盘登录已失效，请重新授权',
        authenticationRequired: true,
      );
    }
    final data = await _getJson(
      '$_oauthBase/oauth/2.0/token',
      query: {
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
        'client_id': source.appKey.trim(),
        'client_secret': current.appSecret,
      },
    );
    _throwOAuthError(data);
    final accessToken = _string(data['access_token']);
    if (accessToken.isEmpty) {
      throw const CloudDriveException(
        '百度网盘登录已失效，请重新授权',
        authenticationRequired: true,
      );
    }
    final expiresIn = _int(data['expires_in']) ?? 2592000;
    await _credentials.write(
      source.id,
      current.copyWith(
        accessToken: accessToken,
        refreshToken: _string(data['refresh_token']).isEmpty
            ? current.refreshToken
            : _string(data['refresh_token']),
        expiresAtMs: DateTime.now()
            .add(Duration(seconds: expiresIn))
            .millisecondsSinceEpoch,
      ),
    );
    return accessToken;
  }

  Future<Map<String, dynamic>> _getJson(
    String url, {
    required Map<String, String> query,
  }) async {
    try {
      final response = await _dio.get<Object?>(url, queryParameters: query);
      final data = response.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw const CloudDriveException('网盘服务器返回了无法识别的数据');
    } on CloudDriveException {
      rethrow;
    } on DioException catch (e) {
      throw CloudDriveException('网络请求失败，请检查网络后重试', cause: e);
    }
  }

  void _throwOAuthError(Map<String, dynamic> data) {
    final error = _string(data['error']);
    final errorCode = _int(data['error_code']) ?? 0;
    if (error.isEmpty && errorCode == 0) return;
    final description = _string(data['error_description']).isNotEmpty
        ? _string(data['error_description'])
        : _string(data['error_msg']);
    throw CloudDriveException(
      description.isEmpty ? '百度网盘授权失败：$error' : description,
      code: errorCode == 0 ? null : errorCode,
      authenticationRequired: true,
    );
  }

  String _normalizePath(String raw) {
    var path = raw.trim().replaceAll('\\', '/');
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  String _joinPath(String parent, String child) {
    if (parent == '/') return '/$child';
    return '$parent/$child';
  }

  String _string(Object? value) => value?.toString() ?? '';

  int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
