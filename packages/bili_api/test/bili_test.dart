import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiliSongId', () {
    test('id 能原样解回 bvid 和 cid', () {
      final id = BiliSongId.buildSongId('BV1Ki4y1y7HC', 123456);
      expect(id, 'bili::BV1Ki4y1y7HC-123456');
      expect(BiliSongId.parseSongId(id), ('BV1Ki4y1y7HC', 123456));
    });

    test('非 B 站 id 解析返回 null', () {
      expect(BiliSongId.parseSongId('webdav-1::/a/b.flac'), isNull);
      expect(BiliSongId.parseSongId('bili::BV1-abc'), isNull);
    });

    test('uri 是稳定占位地址而不是空 —— playQueue 会把空 uri 的歌全滤掉', () {
      final id = BiliSongId.buildSongId('BV1', 456);
      expect(BiliSongId.placeholderUri(id), 'bili://BV1/456');
    });
  });

  group('BiliAudioSelector', () {
    BiliAudioStream stream(int id, int bandwidth) => BiliAudioStream(
      id: id,
      url: 'https://example.com/$id',
      backupUrls: const [],
      bandwidth: bandwidth,
      codecs: 'mp4a',
    );

    test('优先高档位而不是接口给的顺序', () {
      // 30216=64K 排在最前，但 30280=192K 才是该选的那路。
      final best = BiliAudioSelector.best([
        stream(30216, 67301),
        stream(30280, 319076),
        stream(30232, 132791),
      ]);
      expect(best!.id, 30280);
    });

    test('同档位比码率', () {
      final best = BiliAudioSelector.best([
        stream(30280, 100000),
        stream(30280, 320000),
      ]);
      expect(best!.bandwidth, 320000);
    });

    test('空列表返回 null', () {
      expect(BiliAudioSelector.best(const []), isNull);
    });
  });

  group('BiliVideo 解析', () {
    test('剥掉搜索结果标题里的高亮标签和转义', () {
      expect(
        BiliVideo.stripHighlight('周杰伦 <em class="keyword">稻香</em> &amp; 晴天'),
        '周杰伦 稻香 & 晴天',
      );
    });

    test('时长 "mm:ss" 转秒', () {
      expect(BiliVideo.parseDuration('3:43'), 223);
      expect(BiliVideo.parseDuration('1:02:03'), 3723);
      expect(BiliVideo.parseDuration(223), 223);
    });

    test('协议相对的封面地址补上 https', () {
      expect(
        BiliVideo.normalizeCover('//i2.hdslb.com/bfs/archive/x.jpg'),
        'https://i2.hdslb.com/bfs/archive/x.jpg',
      );
    });
  });

  group('BiliSubtitleService', () {
    BiliSubtitleTrack track(String lan, String label) =>
        BiliSubtitleTrack(id: 1, lan: lan, label: label, url: 'https://x/$lan');

    test('LRC 时间戳格式', () {
      expect(BiliSubtitleService.formatTimestamp(0), '00:00.00');
      expect(BiliSubtitleService.formatTimestamp(3.5), '00:03.50');
      expect(BiliSubtitleService.formatTimestamp(65.25), '01:05.25');
      // 有声书动辄一小时以上，LRC 没有小时位，分钟继续往上加而不是回绕。
      expect(BiliSubtitleService.formatTimestamp(3725.6), '62:05.60');
    });

    test('逐句转成 LRC，并补一条结束时间', () {
      final lrc = BiliSubtitleService.toLrc(const [
        BiliSubtitleLine(from: 0, to: 2.5, content: '第一句'),
        BiliSubtitleLine(from: 2.5, to: 5, content: '第二句'),
      ]);
      expect(lrc, '[00:00.00]第一句\n[00:02.50]第二句\n[00:05.00]\n');
    });

    test('优先 UP 上传的字幕，其次 AI，摘要排最后', () {
      final best = BiliSubtitleService.pickBest([
        track('ai-zh', '中文（AI 生成）'),
        track('zh-CN', '中文'),
      ]);
      expect(best!.lan, 'zh-CN');
    });

    test('同为 AI 时中文优先', () {
      final best = BiliSubtitleService.pickBest([
        track('ai-en', 'English（AI）'),
        track('ai-zh', '中文（AI）'),
      ]);
      expect(best!.lan, 'ai-zh');
    });

    test('只有 AI 摘要时返回 null —— 那是一整段总结，做歌词没意义', () {
      expect(
        BiliSubtitleService.pickBest([track('ai-summary', 'AI 摘要')]),
        isNull,
      );
    });

    test('没有任何轨道时返回 null', () {
      expect(BiliSubtitleService.pickBest(const []), isNull);
    });
  });

  group('BiliAccount', () {
    test('cookieHeader 同时带上登录态和风控 cookie', () {
      const account = BiliAccount(
        sessData: 'abc',
        biliJct: 'jct',
        mid: '42',
        anon: {'buvid3': 'B3'},
      );
      expect(
        account.cookieHeader,
        'SESSDATA=abc; bili_jct=jct; DedeUserID=42; buvid3=B3',
      );
      expect(account.isLoggedIn, isTrue);
    });

    test('未登录时 isLoggedIn 为 false', () {
      expect(const BiliAccount(anon: {'buvid3': 'B3'}).isLoggedIn, isFalse);
    });

    test('json 往返保留 anon', () {
      const account = BiliAccount(sessData: 's', anon: {'buvid3': 'B3'});
      final restored = BiliAccount.fromJson(account.toJson());
      expect(restored.anon['buvid3'], 'B3');
      expect(restored.sessData, 's');
    });
  });
}
