import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只测「字幕逐句 → LRC」这一步本身的格式（时间戳精度、结尾补空行）。
///
/// 「App 的 LyricsParser 能不能把这段 LRC 解析回逐句时间轴」是另一条断言，
/// 它跨了包边界（bili_api 不能反过来依赖 app），留在根 test/ 目录的
/// bili_subtitle_lyrics_test.dart 里。
void main() {
  test('逐句转出的 LRC 带正确的时间戳格式', () {
    final lrc = BiliSubtitleService.toLrc(const [
      BiliSubtitleLine(from: 1.2, to: 3.4, content: '第一句'),
      BiliSubtitleLine(from: 3.4, to: 6.0, content: '第二句'),
    ]);
    expect(lrc, '[00:01.20]第一句\n[00:03.40]第二句\n[00:06.00]\n');
  });

  test('超过一小时的时间戳分钟位继续往上加，而不是回绕', () {
    // 有声书一集经常一小时以上，LRC 没有小时位，分钟会写成三位数。
    final lrc = BiliSubtitleService.toLrc(const [
      BiliSubtitleLine(from: 7325.5, to: 7330.0, content: '两小时零五分那句'),
    ]);
    expect(lrc, startsWith('[122:05.50]'));
  });
}
