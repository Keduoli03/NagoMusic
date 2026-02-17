import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/lyrics/lyrics_parser.dart';

void main() {
  test('parse translation line with same timestamp', () {
    const lrc = '''
[00:02.392]Ave [00:02.574]Maria [00:04.301]grazia [00:04.589]ricevuta [00:06.145]per [00:06.318]la [00:06.535]mia [00:06.710]famiglia[00:07.285]
[00:02.392]万福玛利亚 感谢您对于我家族的恩赐[00:15.340]
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    final line = model.lines.firstWhere(
      (l) => l.start == const Duration(milliseconds: 2392),
    );
    expect(line.translation, '万福玛利亚 感谢您对于我家族的恩赐');
  });
}
