import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/components/feedback/app_toast.dart';

void main() {
  testWidgets('Toast 使用纯文字胶囊而不再显示状态图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppToast.show(
                context,
                '已保存',
                duration: const Duration(milliseconds: 1),
              ),
              child: const Text('显示提示'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示提示'));
    await tester.pump();

    expect(find.text('已保存'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
