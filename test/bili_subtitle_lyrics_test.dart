import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_models.dart';
import 'package:nagomusic/app/services/bili/bili_subtitle_service.dart';
import 'package:nagomusic/app/services/lyrics/lyrics_parser.dart';

/// B 站字幕转出来的 LRC 必须能被 App 自己的解析器吃下去 —— 这两边是分开写的，
/// 只测转换不测解析的话，格式对不上也发现不了。
void main() {
  test('字幕转出的 LRC 能被 LyricsParser 解析回逐句时间轴', () {
    final lrc = BiliSubtitleService.toLrc(const [
      BiliSubtitleLine(from: 1.2, to: 3.4, content: '第一句'),
      BiliSubtitleLine(from: 3.4, to: 6.0, content: '第二句'),
    ]);
    final lines = LyricsParser.parseLrc(lrc);

    expect(lines.length, greaterThanOrEqualTo(2));
    expect(lines[0].text, '第一句');
    expect(lines[0].time, const Duration(milliseconds: 1200));
    expect(lines[1].text, '第二句');
    expect(lines[1].time, const Duration(milliseconds: 3400));
  });

  test('超过一小时的时间戳不会被丢掉', () {
    // 有声书一集经常一小时以上，LRC 没有小时位，分钟会写成三位数。
    // 解析器原本只认 1-2 位分钟，这种行会被整条忽略。
    final lrc = BiliSubtitleService.toLrc(const [
      BiliSubtitleLine(from: 7325.5, to: 7330.0, content: '两小时零五分那句'),
    ]);
    expect(lrc, startsWith('[122:05.50]'));

    final lines = LyricsParser.parseLrc(lrc);
    expect(lines, isNotEmpty);
    expect(lines.first.text, '两小时零五分那句');
    expect(lines.first.time, const Duration(minutes: 122, milliseconds: 5500));
  });
}
