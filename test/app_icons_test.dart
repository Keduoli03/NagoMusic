import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

void main() {
  test('收藏图标有明确的空心与实心两态', () {
    expect(AppIcons.star, isNot(AppIconsFilled.star));
  });
}
