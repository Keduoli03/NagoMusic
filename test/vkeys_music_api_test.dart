import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/online_meta/online_metadata_service.dart';
import 'package:nagomusic/app/services/online_meta/vkeys_music_api.dart';
import 'package:nagomusic/app/state/song_state.dart';

SongEntity _song({required String title, required String artist}) {
  return SongEntity(id: 'test', title: title, artist: artist, isLocal: false);
}

void main() {
  group('VkeysSong.fromJson', () {
    test('解析搜索结果的关键字段', () {
      final song = VkeysSong.fromJson({
        'id': 1264448,
        'mid': '000BOihP0oMTAK',
        'song': '爱情好无奈',
        'singer': '六哲',
        'album': '被伤过的心还可以爱谁',
        'cover': 'https://y.qq.com/music/photo_new/T002R800x800M000.jpg',
        'time': '2010-06-21',
        'interval': '3分36秒',
        'grp': [],
      });
      expect(song.id, 1264448);
      expect(song.mid, '000BOihP0oMTAK');
      expect(song.song, '爱情好无奈');
      expect(song.singer, '六哲');
      expect(song.album, '被伤过的心还可以爱谁');
      expect(song.releaseDate, '2010-06-21');
      expect(song.isUsable, isTrue);
    });

    test('展开同名多版本 grp', () {
      final song = VkeysSong.fromJson({
        'id': 1,
        'mid': 'a',
        'song': '梦回还',
        'grp': [
          {'id': 2, 'mid': 'b', 'song': '梦回还', 'album': '……轮转', 'grp': []},
        ],
      });
      expect(song.variants, hasLength(1));
      expect(song.variants.first.album, '……轮转');
    });

    test('缺字段不炸，只是标成不可用', () {
      final song = VkeysSong.fromJson(const {});
      expect(song.song, '');
      expect(song.isUsable, isFalse);
    });

    test('没有歌名的条目不可用', () {
      final song = VkeysSong.fromJson({'id': 1, 'mid': 'a', 'song': ''});
      expect(song.isUsable, isFalse);
    });

    test('有歌名但 id/mid 全缺的条目不可用 —— 取不了歌词', () {
      final song = VkeysSong.fromJson({'song': '某首歌'});
      expect(song.isUsable, isFalse);
    });
  });

  group('VkeysLyrics.toLrc', () {
    const lrc = '[00:26.40]爱一个人好无奈\n[00:32.80]爱过后才明白';
    const trans = '[00:26.40]Loving someone is helpless\n[00:32.80]I see now';

    test('把翻译接在正文后面 —— 同时间戳的行由解析器合并成原文+翻译', () {
      const lyrics = VkeysLyrics(lrc: lrc, trans: trans, yrc: '', roma: '');
      final combined = lyrics.toLrc();
      expect(combined.contains('爱一个人好无奈'), isTrue);
      expect(combined.contains('Loving someone is helpless'), isTrue);
      expect(lyrics.hasTranslation, isTrue);
    });

    test('不要翻译时只给正文', () {
      const lyrics = VkeysLyrics(lrc: lrc, trans: trans, yrc: '', roma: '');
      final combined = lyrics.toLrc(includeTranslation: false);
      expect(combined.contains('Loving someone'), isFalse);
      expect(combined.contains('爱一个人好无奈'), isTrue);
    });

    test('没有翻译时不会拼出多余的空行', () {
      const lyrics = VkeysLyrics(lrc: lrc, trans: '   ', yrc: '', roma: '');
      expect(lyrics.toLrc(), lrc);
      expect(lyrics.hasTranslation, isFalse);
    });

    test('正文为空即视为无歌词', () {
      const lyrics = VkeysLyrics(lrc: '  ', trans: '', yrc: '', roma: '');
      expect(lyrics.isEmpty, isTrue);
    });
  });

  group('OnlineMetadataService.buildQuery', () {
    final service = OnlineMetadataService.instance;

    test('正常标签直接拼歌名 + 歌手', () {
      final q = service.buildQuery(_song(title: '爱情好无奈', artist: '六哲'));
      expect(q, '爱情好无奈 六哲');
    });

    test('文件名式标题去掉前导曲目号', () {
      // WebDAV 扫出来的标题就长这样，原样拿去搜命中率很差。
      final q = service.buildQuery(_song(title: '0038-爱情好无奈-六哲', artist: '六哲'));
      expect(q.startsWith('0038'), isFalse);
      expect(q.contains('爱情好无奈'), isTrue);
    });

    test('标题里已经含歌手时不再重复拼一次', () {
      final q = service.buildQuery(_song(title: '爱情好无奈-六哲', artist: '六哲'));
      expect('六哲'.allMatches(q).length, 1);
    });

    test('去掉方括号里的音质标记', () {
      final q = service.buildQuery(_song(title: '[无损]告白气球', artist: '周杰伦'));
      expect(q.contains('无损'), isFalse);
      expect(q.contains('告白气球'), isTrue);
    });

    test('占位歌手不参与拼接', () {
      // WebDAV 扫描会把音源名写进 artist，「云端」「未知艺术家」都是占位。
      expect(service.buildQuery(_song(title: '晴天', artist: '云端')), '晴天');
      expect(service.buildQuery(_song(title: '晴天', artist: '未知艺术家')), '晴天');
    });

    test('去掉扩展名', () {
      final q = service.buildQuery(_song(title: '晴天.flac', artist: '周杰伦'));
      expect(q.contains('.flac'), isFalse);
    });

    test('标题为空时退回歌手名', () {
      expect(service.buildQuery(_song(title: '  ', artist: '周杰伦')), '周杰伦');
    });
  });
}
