import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_cache/src/audio_proxy_server.dart';

/// 哪些上游错误值得退避重试。
///
/// 「主机名解析不出来」意味着设备当下没有可用 DNS，500ms 后再问结果一样 ——
/// 重试三次只会把一次失败拖成两秒，还刷满日志。其余连接类错误（超时、连接被重置）
/// 是真的可能一会儿就好，必须保留重试。
void main() {
  DioException dioWith(Object inner) => DioException(
    requestOptions: RequestOptions(path: '/'),
    error: inner,
  );

  group('isHostLookupFailure', () {
    test('认出 DNS 解析失败（Dart 各平台统一的那句话）', () {
      final error = dioWith(
        const SocketException(
          "Failed host lookup: 'ol.330840.xyz'",
          osError: OSError('No address associated with hostname', 7),
        ),
      );
      expect(isHostLookupFailure(error), isTrue);
    });

    test('裸 SocketException 也认', () {
      expect(
        isHostLookupFailure(
          const SocketException("Failed host lookup: 'example.com'"),
        ),
        isTrue,
      );
    });

    test('连接超时不算 —— 这种要留着重试', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(isHostLookupFailure(error), isFalse);
    });

    test('连接被重置不算 —— 这种也要留着重试', () {
      final error = dioWith(
        const SocketException(
          'Connection reset by peer',
          osError: OSError('Connection reset by peer', 104),
        ),
      );
      expect(isHostLookupFailure(error), isFalse);
    });

    test('无关异常不算', () {
      expect(isHostLookupFailure(StateError('boom')), isFalse);
    });
  });
}
