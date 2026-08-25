import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _dashPayload({
  List<Map<String, dynamic>>? audio,
  Map<String, dynamic>? flac,
  List<Map<String, dynamic>>? dolby,
}) {
  return {
    'dash': {
      'audio': audio ?? const [],
      if (flac != null) 'flac': {'audio': flac},
      if (dolby != null) 'dolby': {'audio': dolby},
    },
  };
}

Map<String, dynamic> _durlPayload({
  String url = 'https://cdn.example/old.flv',
  List<String> backup = const ['https://backup.example/old.flv'],
  String format = 'flv',
}) {
  return {
    'format': format,
    'durl': [
      {
        'order': 1,
        'length': 600000,
        'size': 12345678,
        'url': url,
        'backup_url': backup,
      },
    ],
  };
}

void main() {
  group('DASH 响应', () {
    test('取出 dash.audio 里的音频流', () {
      final streams = parsePlayurlAudioStreams(
        _dashPayload(
          audio: [
            {'id': 30280, 'baseUrl': 'https://a/192k', 'bandwidth': 192000},
            {'id': 30216, 'baseUrl': 'https://a/64k', 'bandwidth': 64000},
          ],
        ),
      );

      expect(streams, hasLength(2));
      expect(BiliAudioSelector.best(streams)!.id, 30280);
    });

    test('Hi-Res 和杜比不在 dash.audio 里，要单独取到', () {
      final streams = parsePlayurlAudioStreams(
        _dashPayload(
          audio: [
            {'id': 30280, 'baseUrl': 'https://a/192k', 'bandwidth': 192000},
          ],
          flac: {
            'id': 30251,
            'baseUrl': 'https://a/hires',
            'bandwidth': 900000,
          },
          dolby: [
            {'id': 30250, 'baseUrl': 'https://a/dolby', 'bandwidth': 500000},
          ],
        ),
      );

      expect(streams.map((s) => s.id), containsAll([30251, 30250, 30280]));
      expect(
        BiliAudioSelector.best(streams)!.id,
        30251,
        reason: 'Hi-Res 应该排在最前',
      );
    });

    test('url 为空的流被丢掉', () {
      final streams = parsePlayurlAudioStreams(
        _dashPayload(
          audio: [
            {'id': 30280, 'baseUrl': '', 'bandwidth': 192000},
            {'id': 30216, 'baseUrl': 'https://a/64k', 'bandwidth': 64000},
          ],
        ),
      );

      expect(streams, hasLength(1));
      expect(streams.single.id, 30216);
    });
  });

  group('durl 兜底', () {
    // 这组是这次修复的核心：老视频（比如 BV1Xs411o732）没有 DASH 版本，
    // playurl 只给音视频合流的 durl。以前碰到没有 dash 就直接返回空列表，
    // 表现是「取流失败，候选数=0」，视频在网页能放、App 里一声不响放不出来。
    test('没有 dash 字段时退化到 durl', () {
      final streams = parsePlayurlAudioStreams(_durlPayload());

      expect(streams, hasLength(1), reason: '老视频必须还能拿到一路可播的流');
      expect(streams.single.url, 'https://cdn.example/old.flv');
      expect(streams.single.backupUrls, ['https://backup.example/old.flv']);
      expect(BiliAudioSelector.best(streams), isNotNull);
    });

    test('dash 在但一路可用音频都没有时，同样退回 durl', () {
      final payload = <String, dynamic>{
        ..._dashPayload(audio: const []),
        ..._durlPayload(),
      };

      final streams = parsePlayurlAudioStreams(payload);

      expect(streams, hasLength(1));
      expect(streams.single.url, 'https://cdn.example/old.flv');
    });

    test('合流流不报音质 —— bandwidth 为 0，标签为空', () {
      final stream = parsePlayurlAudioStreams(_durlPayload()).single;

      // 合流文件的码率里混着视频，拿它当音质是骗人的，宁可不显示。
      expect(stream.bandwidth, 0);
      expect(stream.qualityLabel, isEmpty);
    });

    test('durl 为空 / 缺 url 时返回空列表', () {
      expect(parsePlayurlAudioStreams({'durl': const []}), isEmpty);
      expect(
        parsePlayurlAudioStreams({
          'durl': [
            {'order': 1},
          ],
        }),
        isEmpty,
      );
    });
  });

  test('既没有 dash 也没有 durl 时返回空列表', () {
    expect(parsePlayurlAudioStreams(const {}), isEmpty);
    expect(BiliAudioSelector.best(const []), isNull);
  });
}
