import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_music_service.dart';
import 'package:nagomusic/app/state/song_state.dart';

/// [BiliMusicService.songsFromDetail] 和曲目标题拼接是 app 侧代码（依赖
/// `SongEntity`），不能跟着 id 编解码 / 音质选择那些纯逻辑一起搬进 bili_api 包，
/// 所以这组测试留在根 test/ 目录。其余 bili 相关的纯逻辑测试已经搬进
/// packages/bili_api/test/bili_test.dart。
void main() {
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
          BiliPart(
            cid: 1,
            index: 1,
            title: '01 三体I-科学边界[2007年]',
            durationSec: 600,
          ),
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
        detail(const [
          BiliPart(cid: 1, index: 1, title: '随便', durationSec: 60),
        ]),
      );
      expect(songs.single.title, '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质');
      expect(songs.single.album, isNull);
    });

    test('uri 是稳定占位地址而不是空 —— playQueue 会把空 uri 的歌全滤掉', () {
      final songs = BiliMusicService.instance.songsFromDetail(
        detail(const [
          BiliPart(cid: 456, index: 1, title: 'x', durationSec: 60),
        ]),
      );
      expect(songs.single.uri, 'bili://BV1/456');
    });
  });

  group('BiliMusicService 文件夹归类', () {
    test('B 站全部归入同一个虚拟文件夹', () {
      const song = SongEntity(
        id: 'bili::BV1ab411c7dD-123',
        title: 'P1',
        artist: 'UP',
        uri: 'bili://BV1ab411c7dD/123',
        isLocal: false,
        sourceId: BiliMusicService.sourceId,
      );

      expect(BiliMusicService.isBiliSong(song), isTrue);
      expect(BiliMusicService.isLibraryFolderPath('bili://B站'), isTrue);
      expect(
        BiliMusicService.isLibraryFolderPath('bili://BV1ab411c7dD'),
        isFalse,
      );
    });
  });
}
