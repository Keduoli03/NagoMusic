// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/app.dart';
import 'package:nagomusic/pages/home/home_page.dart';

void main() {
  testWidgets('Home page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const NagoMusicApp());
    // 首页会预热其它 Tab（见 app_router.dart 的 _warmOne），预热用
    // Future.delayed 定时器在 pumpAndSettle 期间不会结束，导致
    // "A Timer is still pending" 失败；改用有界 pump 只等首帧稳定。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomePage), findsOneWidget);
    // 排空剩余的预热定时器（最晚 1100ms），避免测试结束时框架断言
    // "A Timer is still pending" 失败。
    await tester.pump(const Duration(milliseconds: 1200));
  });
}
