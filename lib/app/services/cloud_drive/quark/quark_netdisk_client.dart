import 'dart:convert';

import 'package:dio/dio.dart';

import '../../log/log.dart';
import '../cloud_drive_credential_store.dart';
import '../cloud_drive_source_repository.dart';
import '../cloud_drive_types.dart';

class QuarkNetdiskClient {
  static const String _logTag = 'QuarkNetdiskClient';
  static const String _apiBase = 'https://drive-pc.quark.cn/1/clouddrive';
  static const String _referer = 'https://pan.quark.cn/';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  final Dio _dio;
  final CloudDriveCredentialStore _credentials;
  final Map<String, Map<String, String>> _loginCookies = {};

  QuarkNetdiskClient({Dio? dio, CloudDriveCredentialStore? credentials})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _credentials = credentials ?? SecureCloudDriveCredentialStore.instance;

  Future<bool> isAuthenticated(String sourceId) async {
    final credentials = await _credentials.read(sourceId);
    return credentials.hasQuarkSession;
  }

  Future<void> logout(String sourceId) async {
    _loginCookies.remove(sourceId);
    await _credentials.delete(sourceId);
  }

  Future<CloudDriveLoginChallenge> beginLogin(CloudDriveSource source) async {
    final cookies = <String, String>{};
    final data = await _requestJson(
      'GET',
      'https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin',
      query: {'client_id': '532', 'v': '1.2', 'request_id': _requestId()},
      cookies: cookies,
      includeDriveDefaults: false,
    );
    if (_int(data['status']) != 2000000) {
      throw CloudDriveException(
        _string(data['message']).isEmpty
            ? '夸克网盘获取登录二维码失败'
            : _string(data['message']),
      );
    }
    final members = _map(_map(data['data'])['members']);
    final token = _string(members['token']);
    if (token.isEmpty) {
      throw const CloudDriveException('夸克网盘没有返回登录令牌');
    }
    _loginCookies[token] = cookies;
    final qrUri = Uri.parse('https://su.quark.cn/4_eMHBJ').replace(
      queryParameters: {
        'token': token,
        'client_id': '532',
        'ssb': 'weblogin',
        'uc_param_str': '',
        'uc_biz_str':
            'S:custom|OPT:SAREA@0|OPT:IMMERSIVE@1|OPT:BACK_BTN_STYLE@0',
      },
    );
    return CloudDriveLoginChallenge(
      id: token,
      qrValue: qrUri.toString(),
      qrValueIsImageUrl: false,
      verificationUrl: qrUri.toString(),
      expiresIn: const Duration(minutes: 5),
      pollInterval: const Duration(seconds: 2),
    );
  }

  Future<CloudDriveLoginStatus> pollLogin(
    CloudDriveSource source,
    CloudDriveLoginChallenge challenge,
  ) async {
    final cookies = _loginCookies.putIfAbsent(
      challenge.id,
      () => <String, String>{},
    );
    final data = await _requestJson(
      'GET',
      'https://uop.quark.cn/cas/ajax/getServiceTicketByQrcodeToken',
      query: {
        'client_id': '532',
        'v': '1.2',
        'token': challenge.id,
        'request_id': _requestId(),
      },
      cookies: cookies,
      includeDriveDefaults: false,
    );
    final status = _int(data['status']);
    if (status == 50004001) return CloudDriveLoginStatus.pending;
    if (status == 50004002 || status == 50004004) {
      _loginCookies.remove(challenge.id);
      return CloudDriveLoginStatus.expired;
    }
    if (status == 50004003) {
      _loginCookies.remove(challenge.id);
      return CloudDriveLoginStatus.denied;
    }
    final members = _map(_map(data['data'])['members']);
    final ticket = _string(members['service_ticket']);
    if (status != 2000000 || ticket.isEmpty) {
      return CloudDriveLoginStatus.pending;
    }

    await _requestJson(
      'GET',
      'https://pan.quark.cn/account/info',
      query: {'st': ticket, 'lw': 'scan'},
      cookies: cookies,
      includeDriveDefaults: false,
      followRedirects: true,
    );
    if (cookies.isEmpty) {
      throw const CloudDriveException('夸克网盘登录成功，但没有返回登录 Cookie');
    }
    final current = await _credentials.read(source.id);
    await _credentials.write(
      source.id,
      current.copyWith(cookie: _cookieHeader(cookies)),
    );
    _loginCookies.remove(challenge.id);
    return CloudDriveLoginStatus.complete;
  }

  Future<List<CloudDriveEntry>> listChildren(
    CloudDriveSource source,
    String parentId,
  ) async {
    final credentials = await _credentials.read(source.id);
    if (credentials.cookie.isEmpty) {
      throw const CloudDriveException('夸克网盘尚未登录', authenticationRequired: true);
    }
    final cookies = _parseCookieHeader(credentials.cookie);
    final result = <CloudDriveEntry>[];
    var page = 1;
    const pageSize = 100;
    while (true) {
      final data = await _driveRequest(
        'GET',
        '/file/sort',
        query: {
          'pdir_fid': parentId.isEmpty ? '0' : parentId,
          '_page': '$page',
          '_size': '$pageSize',
          '_fetch_total': '1',
          'fetch_all_file': '1',
          'fetch_risk_file_name': '1',
          '_sort': 'file_type:asc,file_name:asc',
        },
        cookies: cookies,
      );
      final dataBody = _map(data['data']);
      final rawList = dataBody['list'];
      final entries = rawList is List
          ? rawList.whereType<Map>().map((raw) {
              final item = raw.cast<String, dynamic>();
              final isFile = item['file'] == true || _int(item['isdir']) == 0;
              return CloudDriveEntry(
                id: _string(item['fid']),
                name: _string(item['file_name']),
                parentId: parentId,
                path: _string(item['file_name']),
                isDirectory: !isFile,
                size: _int(item['size']),
                modifiedMs:
                    _int(item['updated_at']) ?? _int(item['l_updated_at']),
                durationMs: _normalizeDuration(_int(item['duration'])),
              );
            }).toList()
          : const <CloudDriveEntry>[];
      result.addAll(entries);
      final metadata = _map(data['metadata']);
      final total = _int(metadata['_total']) ?? result.length;
      if (entries.length < pageSize || result.length >= total) break;
      page += 1;
    }
    await _persistCookiesIfChanged(source.id, credentials, cookies);
    return result;
  }

  Future<bool> testConnection(CloudDriveSource source) async {
    try {
      await listChildren(source, source.root);
      return true;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '测试夸克网盘连接失败 sourceId=${source.id}', e, s);
      return false;
    }
  }

  Future<CloudDrivePlaybackLink> resolvePlaybackLink(
    CloudDriveSource source,
    String fileId, {
    bool forceRefresh = false,
  }) async {
    final credentials = await _credentials.read(source.id);
    if (credentials.cookie.isEmpty) {
      throw const CloudDriveException(
        '夸克网盘登录已失效，请重新扫码登录',
        authenticationRequired: true,
      );
    }
    final cookies = _parseCookieHeader(credentials.cookie);
    final data = await _driveRequest(
      'POST',
      '/file/download',
      query: const {'sys': 'win32', 've': '2.5.56', 'ut': '', 'guid': ''},
      body: {
        'fids': [fileId],
      },
      cookies: cookies,
    );
    final rawList = data['data'];
    if (rawList is! List || rawList.isEmpty || rawList.first is! Map) {
      throw const CloudDriveException('夸克网盘没有返回文件下载地址');
    }
    final downloadUrl = _string((rawList.first as Map)['download_url']);
    if (downloadUrl.isEmpty) {
      throw const CloudDriveException('夸克网盘文件暂时无法下载');
    }
    await _persistCookiesIfChanged(source.id, credentials, cookies);
    final cookie = _cookieHeader(cookies);
    return CloudDrivePlaybackLink(
      uri: Uri.parse(downloadUrl),
      headers: {
        'Cookie': cookie,
        'Referer': _referer,
        'User-Agent': _userAgent,
        'Accept': '*/*',
      },
    );
  }

  Future<Map<String, String>> playbackHeaders(CloudDriveSource source) async {
    final credentials = await _credentials.read(source.id);
    if (credentials.cookie.isEmpty) {
      throw const CloudDriveException(
        '夸克网盘登录已失效，请重新扫码登录',
        authenticationRequired: true,
      );
    }
    return {
      'Cookie': credentials.cookie,
      'Referer': _referer,
      'User-Agent': _userAgent,
      'Accept': '*/*',
    };
  }

  Future<Map<String, dynamic>> _driveRequest(
    String method,
    String path, {
    Map<String, String> query = const {},
    Object? body,
    required Map<String, String> cookies,
  }) async {
    final data = await _requestJson(
      method,
      '$_apiBase$path',
      query: query,
      body: body,
      cookies: cookies,
    );
    final status = _int(data['status']) ?? 200;
    final code = _int(data['code']) ?? 0;
    if (status >= 400 || code != 0) {
      final message = _string(data['message']).isEmpty
          ? '夸克网盘请求失败（$code）'
          : _string(data['message']);
      final lower = message.toLowerCase();
      final authRequired =
          status == 401 ||
          status == 403 ||
          lower.contains('login') ||
          lower.contains('cookie') ||
          lower.contains('登录');
      throw CloudDriveException(
        authRequired ? '夸克网盘登录已失效，请重新扫码登录' : message,
        code: code,
        authenticationRequired: authRequired,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String url, {
    Map<String, String> query = const {},
    Object? body,
    required Map<String, String> cookies,
    bool includeDriveDefaults = true,
    bool followRedirects = false,
  }) async {
    final requestQuery = <String, String>{
      if (includeDriveDefaults) ...{
        'pr': 'ucpro',
        'fr': 'pc',
        'uc_param_str': '',
        '__t': '${DateTime.now().millisecondsSinceEpoch}',
        '__dt': '1000',
      },
      ...query,
    };
    try {
      final response = await _dio.request<Object?>(
        url,
        data: body,
        queryParameters: requestQuery,
        options: Options(
          method: method,
          followRedirects: followRedirects,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Origin': 'https://pan.quark.cn',
            'Referer': _referer,
            if (body != null) 'Content-Type': 'application/json',
            if (cookies.isNotEmpty) 'Cookie': _cookieHeader(cookies),
          },
        ),
      );
      _mergeSetCookies(cookies, response.headers.map['set-cookie']);
      final data = response.data;
      if (data is Map) return data.cast<String, dynamic>();
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
      throw const CloudDriveException('夸克网盘返回了无法识别的数据');
    } on CloudDriveException {
      rethrow;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw CloudDriveException(
        status == 401 || status == 403
            ? '夸克网盘登录已失效，请重新扫码登录'
            : '夸克网盘网络请求失败，请检查网络后重试',
        authenticationRequired: status == 401 || status == 403,
        cause: e,
      );
    } on FormatException catch (e) {
      throw CloudDriveException('夸克网盘返回了无法识别的数据', cause: e);
    }
  }

  Future<void> _persistCookiesIfChanged(
    String sourceId,
    CloudDriveCredentials current,
    Map<String, String> cookies,
  ) async {
    final value = _cookieHeader(cookies);
    if (value.isEmpty || value == current.cookie) return;
    await _credentials.write(sourceId, current.copyWith(cookie: value));
  }

  void _mergeSetCookies(Map<String, String> target, List<String>? setCookies) {
    if (setCookies == null) return;
    for (final raw in setCookies) {
      final pair = raw.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (value.isEmpty) {
        target.remove(name);
      } else {
        target[name] = value;
      }
    }
  }

  Map<String, String> _parseCookieHeader(String raw) {
    final result = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      result[part.substring(0, separator).trim()] = part
          .substring(separator + 1)
          .trim();
    }
    return result;
  }

  String _cookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  String _requestId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final hash = identityHashCode(Object()).toRadixString(16);
    return '$now-$hash';
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  String _string(Object? value) => value?.toString() ?? '';

  int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  int? _normalizeDuration(int? raw) {
    if (raw == null || raw <= 0) return null;
    return raw < 100000 ? raw * 1000 : raw;
  }
}
