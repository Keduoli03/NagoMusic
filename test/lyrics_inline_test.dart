import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/lyrics/lyrics_parser.dart';

void main() {
  test('T-ara DAY BY DAY inline single-space bilingual format', () {
    const lrc = '''
[ti:DAY BY DAY (一天一天) (Japanese ver.)]
[ar:T-ara (티아라)]
[00:00.00]DAY BY DAY (Japanese ver.) - T-ara
[00:05.70]词：間智子
[00:11.41]曲：Choo Young Soo/Kim Tae Hyun
[00:17.12]あんなに愛した君がいない 这样珍爱的你不在身边
[00:20.80]Ah 孤独がジリジリ押し寄せる 就这样被孤独感慢慢吞噬
[00:29.04]Kiss me ma baby
[00:37.83]滲んでいるわ 朦胧依旧
[00:45.78]涙が tok tok tok 泪水满襟
[00:57.82]夢のような思い出も 如梦境般的回忆
[01:01.89]消えてしまうの? tok tok tok 也终将消失吗?
[01:05.59]Kiss me baby I'll must be stay here day by day
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );

    LyricLineView at(int ms) {
      final l = model.lines.firstWhere((e) => e.start.inMilliseconds == ms);
      return LyricLineView(l.text, l.translation);
    }

    // JP original + ZH translation
    expect(at(37830).text, '滲んでいるわ');
    expect(at(37830).translation, '朦胧依旧');

    // JP + English onomatopoeia in the ORIGINAL + ZH translation
    expect(at(45780).text, '涙が tok tok tok');
    expect(at(45780).translation, '泪水满襟');

    // JP with English word "Ah" prefix
    expect(at(20800).text, 'Ah 孤独がジリジリ押し寄せる');
    expect(at(20800).translation, '就这样被孤独感慢慢吞噬');

    // Trailing Chinese with ASCII punctuation
    expect(at(61890).text, '消えてしまうの? tok tok tok');
    expect(at(61890).translation, '也终将消失吗?');

    // Pure-English line: NO translation split
    expect(at(29040).text, 'Kiss me ma baby');
    expect(at(29040).translation, isNull);
    expect(at(65590).text, 'Kiss me baby I\'ll must be stay here day by day');
    expect(at(65590).translation, isNull);

    // Whole model has translation -> 译 button should appear
    final hasTranslation = model.lines.any(
      (l) => (l.translation ?? '').trim().isNotEmpty,
    );
    expect(hasTranslation, isTrue);
  });
}

class LyricLineView {
  final String text;
  final String? translation;
  LyricLineView(this.text, this.translation);
}
