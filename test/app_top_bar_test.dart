import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:nagomusic/components/layout/base/app_top_bar.dart';

void main() {
  testWidgets('顶栏可以收紧返回键与标题之间的空隙', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: AppTopBar(
            title: '收藏的视频',
            leading: Icon(AppIcons.chevronLeft),
            leadingWidth: 48,
            titleSpacing: 4,
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.text('收藏的视频')).dx, closeTo(52, 1));
  });
}
