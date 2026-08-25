import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/components/layout/base/app_page_scaffold.dart';
import 'package:nagomusic/components/layout/base/app_top_bar.dart';

const Key _marker = Key('body-marker');

/// 模拟真机：44 状态栏 + 48 导航栏。
///
/// [keyboard] 大于 0 时按 Flutter 的真实行为构造数据 —— 键盘顶起来时
/// `viewInsets.bottom` 变大，而 `padding.bottom` 会被钳成 0
/// （`padding = viewPadding - viewInsets`），`viewPadding` 保持不变。
Widget wrap(Widget child, {double keyboard = 0}) {
  const systemBottom = 48.0;
  return MediaQuery(
    data: MediaQueryData(
      viewPadding: const EdgeInsets.only(top: 44, bottom: systemBottom),
      padding: EdgeInsets.only(
        top: 44,
        bottom: (systemBottom - keyboard).clamp(0.0, systemBottom),
      ),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: MaterialApp(home: child),
  );
}

Widget scaffold({Widget? body}) => AppPageScaffold(
  showMiniPlayer: false,
  appBar: const AppTopBar(title: '搜索'),
  body:
      body ??
      const Align(
        alignment: Alignment.bottomLeft,
        child: SizedBox(key: _marker, width: 10, height: 10),
      ),
);

void main() {
  testWidgets('正文紧接顶栏，中间不多空一条状态栏', (tester) async {
    await tester.pumpWidget(
      wrap(
        scaffold(
          body: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(key: _marker, width: 10, height: 10),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(_marker)).dy,
      closeTo(tester.getBottomLeft(find.byType(AppTopBar)).dy, 0.5),
      reason: '正文应该紧接顶栏，中间不该有状态栏高度的空白',
    );
  });

  testWidgets('键盘弹起时正文不动', (tester) async {
    await tester.pumpWidget(wrap(scaffold()));
    final before = tester.getBottomLeft(find.byKey(_marker)).dy;

    // 同一棵树，只把 MediaQuery 换成"键盘已弹起"的数据。
    await tester.pumpWidget(wrap(scaffold(), keyboard: 300));
    final after = tester.getBottomLeft(find.byKey(_marker)).dy;

    expect(
      after,
      closeTo(before, 0.5),
      reason: '键盘弹起不该让正文移动 —— padding.bottom 塌成 0 时要用 viewPadding 复原',
    );
  });

  testWidgets('列表底部留白不受键盘影响', (tester) async {
    // 页面实际上是在构造 AppPageScaffold **之前**算这个值的（build 方法开头），
    // 也就是说调用点在 scaffold 之上，享受不到正文那层 MediaQuery 修正。
    // 这里照着真实用法把 Builder 放在 scaffold 外面。
    double? captured;

    Widget page() => Builder(
      builder: (context) {
        captured = AppPageScaffold.scrollableBottomPadding(context);
        return scaffold();
      },
    );

    await tester.pumpWidget(wrap(page()));
    final normal = captured!;

    await tester.pumpWidget(wrap(page(), keyboard: 300));
    final withKeyboard = captured!;

    expect(
      withKeyboard,
      closeTo(normal, 0.5),
      reason: '键盘弹起不该改变列表底部留白，否则整个列表会窜一下',
    );
  });
}
