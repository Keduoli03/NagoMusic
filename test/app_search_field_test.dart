import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:nagomusic/components/common/app_search_field.dart';
import 'package:nagomusic/components/layout/base/app_top_bar.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<void> pumpInTopBar(
    WidgetTester tester, {
    VoidCallback? onClear,
    VoidCallback? onSubmit,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppTopBar(
            leading: IconButton(
              icon: const Icon(AppIcons.chevronLeft),
              onPressed: () {},
            ),
            titleWidget: AppSearchField(
              controller: controller,
              hintText: '搜索歌曲',
              onClear: onClear,
            ),
            titleSpacing: 0,
            actions: [
              TextButton(onPressed: onSubmit ?? () {}, child: const Text('搜索')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('搜索框净高 38，没有被 InputDecoration 撑高', (tester) async {
    await pumpInTopBar(tester);

    expect(
      tester.getSize(find.byType(AppSearchField)).height,
      closeTo(38, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回箭头、放大镜、搜索按钮落在同一条中线上', (tester) async {
    await pumpInTopBar(tester);

    final back = tester.getCenter(find.byIcon(AppIcons.chevronLeft)).dy;
    final field = tester.getCenter(find.byType(AppSearchField)).dy;
    final magnifier = tester.getCenter(find.byIcon(AppIcons.search)).dy;
    final action = tester.getCenter(find.text('搜索')).dy;

    expect(field, closeTo(back, 0.5), reason: '搜索框要和返回箭头同一中线');
    expect(magnifier, closeTo(back, 0.5), reason: '框内放大镜要和返回箭头同一中线');
    expect(action, closeTo(back, 0.5), reason: '右侧搜索按钮要和返回箭头同一中线');
  });

  testWidgets('右侧有搜索按钮，点得动', (tester) async {
    var submitted = false;
    await pumpInTopBar(tester, onSubmit: () => submitted = true);

    expect(find.text('搜索'), findsOneWidget);
    await tester.tap(find.text('搜索'));
    await tester.pump();
    expect(submitted, isTrue);
  });

  testWidgets('有内容才出现清空按钮，点了会清空并回调', (tester) async {
    var cleared = false;
    await pumpInTopBar(tester, onClear: () => cleared = true);

    expect(find.byIcon(AppIcons.close), findsNothing);

    await tester.enterText(find.byType(TextField), '晴天');
    await tester.pump();
    expect(find.byIcon(AppIcons.close), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(cleared, isTrue);
    expect(find.byIcon(AppIcons.close), findsNothing);
  });
}
