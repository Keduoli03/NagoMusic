import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/lyrics/lyrics_parser.dart';

/// 真实响应片段（api.vkeys.cn，id=1264448「爱情好无奈」），只截了前几行。
///
/// 关键点：行头 `[26400,6050]` 之后，第一个字的时间是 `(26400,550)` —— 起始值
/// 和行首**相同**，说明逐字时间是绝对的，不是相对行首的偏移。
const _yrc = '''
[ti:爱情好无奈]
[ar:六哲]
[offset:0]
[26400,6050]爱(26400,550)一(26950,1150)个(28100,200)人(28300,450)好(28750,250)无(29000,200)奈(29200,1500)
[32800,2160]爱(32800,650)过(33450,200)后(33650,350)才(34000,300)明(34300,350)白(34650,306)
''';

void main() {
  group('parseYrc', () {
    test('跳过元数据行，只留有时间的行', () {
      final lines = LyricsParser.parseYrc(_yrc);
      expect(lines, hasLength(2));
    });

    test('行文本是各字拼起来的', () {
      final lines = LyricsParser.parseYrc(_yrc);
      expect(lines[0].text, '爱一个人好无奈');
      expect(lines[1].text, '爱过后才明白');
    });

    test('行起始与行尾按 [起始,时长] 算', () {
      final line = LyricsParser.parseYrc(_yrc).first;
      expect(line.start, const Duration(milliseconds: 26400));
      expect(line.end, const Duration(milliseconds: 26400 + 6050));
    });

    test('逐字时间按绝对值解析 —— 写成相对偏移会整首跑偏', () {
      final words = LyricsParser.parseYrc(_yrc).first.words!;
      expect(words, hasLength(7));
      expect(words[0].text, '爱');
      expect(words[0].start, const Duration(milliseconds: 26400));
      expect(words[0].end, const Duration(milliseconds: 26950));
      // 第二个字 26950 = 26400 + 550，正好接在第一个字后面。
      expect(words[1].text, '一');
      expect(words[1].start, const Duration(milliseconds: 26950));
      expect(words[1].end, const Duration(milliseconds: 28100));
      // 最后一个字：29200 + 1500
      expect(words.last.text, '奈');
      expect(words.last.end, const Duration(milliseconds: 30700));
    });

    test('字里带空格时保留空格，不并进相邻字', () {
      final lines = LyricsParser.parseYrc(
        '[100,900]悲(100,300)哀 (400,400)那(800,200)',
      );
      final words = lines.first.words!;
      expect(words[1].text, '哀 ');
      expect(lines.first.text, '悲哀 那');
    });

    test('多带一个字段的 (start,dur,0) 也认', () {
      final lines = LyricsParser.parseYrc('[0,500]好(0,250,0)的(250,250,0)');
      expect(lines.first.words, hasLength(2));
      expect(lines.first.text, '好的');
    });

    test('时长为 0 的字不会产生零长区间', () {
      final lines = LyricsParser.parseYrc('[0,100]啊(0,0)');
      final word = lines.first.words!.single;
      expect(word.end!.inMilliseconds, greaterThan(word.start.inMilliseconds));
    });

    test('普通 LRC 喂进来解析不出东西，而不是崩', () {
      expect(LyricsParser.parseYrc('[00:26.40]爱一个人好无奈'), isEmpty);
      expect(LyricsParser.parseYrc(''), isEmpty);
    });

    test('行按时间排序', () {
      final lines = LyricsParser.parseYrc(
        '[5000,500]后(5000,500)\n[1000,500]先(1000,500)',
      );
      expect(lines.first.text, '先');
      expect(lines.last.text, '后');
    });
  });

  group('buildModelFromYrc', () {
    test('产出带逐字信息的模型', () {
      final model = LyricsParser.buildModelFromYrc(_yrc)!;
      expect(model.lines, hasLength(2));
      expect(model.lines.first.words, isNotNull);
      expect(model.lines.first.words!.first.text, '爱');
    });

    test('从普通 LRC 里按时间戳贴回翻译', () {
      // yrc 本身不带翻译，翻译只能从另一份歌词取。
      const lrc =
          '[00:26.40]爱一个人好无奈\n[00:26.40]Loving someone is helpless\n'
          '[00:32.80]爱过后才明白\n[00:32.80]I understood after loving';
      final model = LyricsParser.buildModelFromYrc(
        _yrc,
        translationSource: lrc,
      )!;
      expect(model.lines.first.translation, 'Loving someone is helpless');
      expect(model.lines.last.translation, 'I understood after loving');
      // 逐字信息不能因为贴翻译而丢掉。
      expect(model.lines.first.words, isNotNull);
    });

    test('没有翻译源时逐字信息照常，translation 为空', () {
      final model = LyricsParser.buildModelFromYrc(_yrc)!;
      expect(model.lines.first.translation, isNull);
      expect(model.lines.first.words, isNotNull);
    });

    test('解析不出内容时返回 null，让调用方退回普通 LRC', () {
      expect(LyricsParser.buildModelFromYrc(''), isNull);
      expect(LyricsParser.buildModelFromYrc('[00:26.40]普通歌词'), isNull);
    });

    test('逐字时间保持单调递增，不会被归一化打乱', () {
      final model = LyricsParser.buildModelFromYrc(_yrc)!;
      for (final line in model.lines) {
        final words = line.words!;
        for (var i = 0; i < words.length; i++) {
          expect(
            words[i].end!.inMilliseconds,
            greaterThan(words[i].start.inMilliseconds),
            reason: '第 $i 个字的区间必须非空',
          );
          if (i > 0) {
            expect(
              words[i].start.inMilliseconds,
              greaterThanOrEqualTo(words[i - 1].start.inMilliseconds),
            );
          }
        }
      }
    });
  });
}
