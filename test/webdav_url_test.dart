import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/webdav/webdav_url.dart';

void main() {
  group('parseWebDavEndpoint', () {
    test('裸地址不带协议时 scheme 为 null，等着自动探测', () {
      final parts = parseWebDavEndpoint('ol.330840.xyz/dav');
      expect(parts.scheme, isNull);
      expect(parts.host, 'ol.330840.xyz');
      expect(parts.port, isNull);
      expect(parts.path, '/dav');
    });

    test('带协议和端口', () {
      final parts = parseWebDavEndpoint('http://10.0.0.2:5244/dav/');
      expect(parts.scheme, 'http');
      expect(parts.host, '10.0.0.2');
      expect(parts.port, 5244);
      expect(parts.path, '/dav');
    });

    test('URL 内联账号密码', () {
      final parts = parseWebDavEndpoint('https://autumn:pw@example.com/dav');
      expect(parts.host, 'example.com');
      expect(parts.username, 'autumn');
      expect(parts.password, 'pw');
    });

    test('IPv6 带端口', () {
      final parts = parseWebDavEndpoint('[::1]:8080/dav');
      expect(parts.host, '[::1]');
      expect(parts.port, 8080);
    });

    test('前后空白和换行不影响解析', () {
      final parts = parseWebDavEndpoint('  https://a.com/dav \n');
      expect(parts.host, 'a.com');
      expect(parts.path, '/dav');
    });
  });

  group('buildWebDavEndpoint', () {
    test('默认端口省略不写', () {
      expect(
        buildWebDavEndpoint(scheme: 'https', host: 'a.com', port: 443),
        'https://a.com',
      );
      expect(
        buildWebDavEndpoint(scheme: 'http', host: 'a.com', port: 80),
        'http://a.com',
      );
    });

    test('非默认端口保留', () {
      expect(
        buildWebDavEndpoint(
          scheme: 'http',
          host: 'a.com',
          port: 5244,
          path: 'dav',
        ),
        'http://a.com:5244/dav',
      );
    });
  });

  group('webDavEndpointCandidates', () {
    test('没写协议时先 https 后 http', () {
      expect(webDavEndpointCandidates('ol.330840.xyz/dav'), [
        'https://ol.330840.xyz/dav',
        'http://ol.330840.xyz/dav',
      ]);
    });

    test('写了协议就只试那一个，不偷偷换', () {
      expect(webDavEndpointCandidates('http://nas.lan/dav'), [
        'http://nas.lan/dav',
      ]);
    });

    test('forcedScheme 覆盖输入里的协议', () {
      expect(
        webDavEndpointCandidates('http://nas.lan/dav', forcedScheme: 'https'),
        ['https://nas.lan/dav'],
      );
    });
  });

  group('normalizeWebDavEndpoint', () {
    test('缺协议时兜底补 https', () {
      expect(normalizeWebDavEndpoint('nas.lan/dav'), 'https://nas.lan/dav');
    });

    test('结尾斜杠去掉，避免拼出 //', () {
      expect(
        normalizeWebDavEndpoint('https://a.com/dav/'),
        'https://a.com/dav',
      );
    });
  });

  group('parseWebDavPaste', () {
    test('认出 key: value 三行', () {
      final r = parseWebDavPaste(
        'url:ol.330840.xyz/dav\naccount:autumn\npassword:He110120',
      );
      expect(r.endpoint, 'ol.330840.xyz/dav');
      expect(r.username, 'autumn');
      expect(r.password, 'He110120');
    });

    test('中文键名和全角冒号', () {
      final r = parseWebDavPaste('地址：https://a.com/dav\n账号：bob\n密码：123');
      expect(r.endpoint, 'https://a.com/dav');
      expect(r.username, 'bob');
      expect(r.password, '123');
    });

    test('裸链接单独一行不会被冒号拆坏', () {
      final r = parseWebDavPaste('https://a.com:8443/dav');
      expect(r.endpoint, 'https://a.com:8443/dav');
    });

    test('识别不出任何字段时返回空结果', () {
      expect(parseWebDavPaste('随便一段没有配置的文字').isEmpty, isTrue);
    });
  });
}
