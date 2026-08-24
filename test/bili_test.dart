import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_audio_selector.dart';
import 'package:nagomusic/app/services/bili/bili_cookie_repository.dart';
import 'package:nagomusic/app/services/bili/bili_models.dart';
import 'package:nagomusic/app/services/bili/bili_music_service.dart';
import 'package:nagomusic/app/services/bili/bili_subtitle_service.dart';

void main() {
  group('BiliMusicService song id', () {
    test('id 能原样解回 bvid 和 cid', () {
      final id = BiliMusicService.buildSongId('BV1Ki4y1y7HC', 123456);
      expect(id, 'bili::BV1Ki4y1y7HC-123456');
      expect(BiliMusicService.parseSongId(id), ('BV1Ki4y1y7HC', 123456));
    });

    test('非 B 站 id 解析返回 null', () {
      expect(BiliMusicService.parseSongId('webdav-1::/a/b.flac'), isNull);
      expect(BiliMusicService.parseSongId('bili::BV1-abc'), isNull);
    });
  });

  group('BiliMusicService 曲目标题', () {
    BiliVideoDetail detail(List<BiliPart> parts) => BiliVideoDetail(
      video: const BiliVideo(
        bvid: 'BV1',
        aid: 1,
        title: '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质',
        author: '读客熊猫君',
        cover: '',
        durationSec: 100,
      ),
      parts: parts,
    );

    test('多 P 且分 P 有独立名字时，标题只用分 P 名', () {
      final songs = BiliMusicService.instance.songsFromDetail(
        detail(const [
          BiliPart(cid: 1, index: 1, title: '01 三体I-科学边界[2007年]', durationSec: 600),
          BiliPart(cid: 2, index: 2, title: '02 三体I-台球', durationSec: 620),
        ]),
      );
      // 视频标题不能拼进曲名，否则列表里一行放不下、分 P 名被挤掉。
      expect(songs[0].title, '01 三体I-科学边界[2007年]');
      expect(songs[1].title, '02 三体I-台球');
      // 但视频标题要留在 album 里，专辑分组还得靠它。
      expect(songs[0].album, '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质');
      expect(songs[0].trackNumber, 1);
    });

    test('分 P 名与视频标题相同时补上视频标题，否则光一个 P1 认不出来', () {
      const title = '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质';
      final songs = BiliMusicService.instance.songsFromDetail(
        detail(const [
          BiliPart(cid: 1, index: 1, title: title, durationSec: 600),
          BiliPart(cid: 2, index: 2, title: title, durationSec: 620),
        ]),
      );
      expect(songs[0].title, '$title · P1');
      expect(songs[1].title, '$title · P2');
    });

    test('单 P 视频直接用视频标题，不带 P 后缀', () {
      final songs = BiliMusicService.instance.songsFromDetail(
        detail(const [BiliPart(cid: 1, index: 1, title: '随便', durationSec: 60)]),
      );
      expect(songs.single.title, '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质');
      expect(songs.single.album, isNull);
    });

    test('uri 是稳定占位地址而不是空 —— playQueue 会把空 uri 的歌全滤掉', () {
      final songs = BiliMusicService.instance.songsFromDetail(
        detail(const [BiliPart(cid: 456, index: 1, title: 'x', durationSec: 60)]),
      );
      expect(songs.single.uri, 'bili://BV1/456');
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
      expect(account.cookieHeader, 'SESSDATA=abc; bili_jct=jct; DedeUserID=42; buvid3=B3');
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
