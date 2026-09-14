import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/services/cloud_drive/baidu/baidu_netdisk_client.dart';
import 'package:nagomusic/app/services/cloud_drive/cloud_drive_credential_store.dart';
import 'package:nagomusic/app/services/cloud_drive/cloud_drive_source_repository.dart';
import 'package:nagomusic/app/services/cloud_drive/cloud_drive_types.dart';
import 'package:nagomusic/app/services/cloud_drive/quark/quark_netdisk_client.dart';

void main() {
  group('BaiduNetdiskClient', () {
    test(
      'device login exposes the QR image and browser fallback code',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeAdapter((_) {
          return _jsonResponse({
            'device_code': 'device-code',
            'user_code': 'ABCD1234',
            'verification_url': 'https://openapi.baidu.com/device',
            'qrcode_url': 'https://openapi.baidu.com/device/qrcode/value',
            'expires_in': 1800,
            'interval': 5,
          });
        });
        final credentials = _MemoryCredentialStore({});
        final client = BaiduNetdiskClient(dio: dio, credentials: credentials);
        const source = CloudDriveSource(
          id: 'baidu-login',
          name: 'Baidu',
          provider: CloudDriveProvider.baidu,
          root: '/',
          appKey: 'app-key',
        );

        final challenge = await client.beginLogin(
          source,
          appSecret: 'app-secret',
        );

        expect(challenge.qrValueIsImageUrl, isTrue);
        expect(challenge.userCode, 'ABCD1234');
        expect(challenge.verificationUrl, 'https://openapi.baidu.com/device');
        expect((await credentials.read(source.id)).appSecret, 'app-secret');
      },
    );

    test('lists files and resolves a tokenized dlink', () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) {
        requests.add(options);
        if (options.queryParameters['method'] == 'filemetas') {
          return _jsonResponse({
            'errno': 0,
            'list': [
              {'dlink': 'https://d.pcs.baidu.com/file/audio'},
            ],
          });
        }
        return _jsonResponse({
          'errno': 0,
          'list': [
            {
              'fs_id': 42,
              'server_filename': 'song.flac',
              'path': '/music/song.flac',
              'isdir': 0,
              'size': 123,
              'server_mtime': 10,
            },
          ],
        });
      });
      final credentials = _MemoryCredentialStore({
        'baidu-1': CloudDriveCredentials(
          accessToken: 'access-token',
          expiresAtMs: DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      });
      final client = BaiduNetdiskClient(dio: dio, credentials: credentials);
      const source = CloudDriveSource(
        id: 'baidu-1',
        name: 'Baidu',
        provider: CloudDriveProvider.baidu,
        root: '/music',
        appKey: 'app-key',
      );

      final entries = await client.listChildren(source, source.root);
      final link = await client.resolvePlaybackLink(source, entries.single.id);

      expect(entries.single.name, 'song.flac');
      expect(entries.single.modifiedMs, 10000);
      expect(link.uri.queryParameters['access_token'], 'access-token');
      expect(link.headers['User-Agent'], BaiduNetdiskClient.downloadUserAgent);
      expect(
        requests.every(
          (request) =>
              request.queryParameters['access_token'] == 'access-token',
        ),
        isTrue,
      );
    });
  });

  group('QuarkNetdiskClient', () {
    test('sends the saved cookie for list and download requests', () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((options) {
        requests.add(options);
        if (options.path.endsWith('/file/download')) {
          return _jsonResponse({
            'status': 200,
            'code': 0,
            'data': [
              {'download_url': 'https://download.quark.cn/audio'},
            ],
          });
        }
        return _jsonResponse({
          'status': 200,
          'code': 0,
          'data': {
            'list': [
              {
                'fid': 'file-1',
                'file_name': 'song.mp3',
                'file': true,
                'size': 99,
              },
            ],
          },
          'metadata': {'_total': 1},
        });
      });
      final client = QuarkNetdiskClient(
        dio: dio,
        credentials: _MemoryCredentialStore({
          'quark-1': const CloudDriveCredentials(cookie: '__puus=session'),
        }),
      );
      const source = CloudDriveSource(
        id: 'quark-1',
        name: 'Quark',
        provider: CloudDriveProvider.quark,
        root: '0',
      );

      final entries = await client.listChildren(source, source.root);
      final link = await client.resolvePlaybackLink(source, entries.single.id);

      expect(entries.single.name, 'song.mp3');
      expect(link.uri.toString(), 'https://download.quark.cn/audio');
      expect(link.headers['Cookie'], '__puus=session');
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (request) => request.headers['Cookie'] == '__puus=session',
        ),
        isTrue,
      );
      expect(requests.last.data, {
        'fids': ['file-1'],
      });
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryCredentialStore implements CloudDriveCredentialStore {
  final Map<String, CloudDriveCredentials> values;

  _MemoryCredentialStore(this.values);

  @override
  Future<void> delete(String sourceId) async {
    values.remove(sourceId);
  }

  @override
  Future<CloudDriveCredentials> read(String sourceId) async {
    return values[sourceId] ?? const CloudDriveCredentials();
  }

  @override
  Future<void> write(String sourceId, CloudDriveCredentials credentials) async {
    values[sourceId] = credentials;
  }
}
