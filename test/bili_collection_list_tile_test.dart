import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_collection_service.dart';
import 'package:nagomusic/app/theme/app_theme.dart';
import 'package:nagomusic/pages/bili/widgets/bili_collection_list_tile.dart';

const _collection = BiliVideoCollection(
  detail: BiliVideoDetail(
    video: BiliVideo(
      bvid: 'BV1history',
      aid: 1,
      title: '有声小说《三体》（读客熊猫君）第一部纯享版',
      author: '垂钓的渔夫',
      cover: '',
      durationSec: 49865,
    ),
    parts: [
      BiliPart(cid: 3, index: 3, title: '03三体｜台球【2007年】', durationSec: 695),
    ],
  ),
  addedAtMs: 1,
  lastCid: 3,
  positionMs: 53000,
);

Widget _host({required VoidCallback onTap, VoidCallback? onLongPress}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 375,
        child: BiliCollectionListTile(
          collection: _collection,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
    useMaterial3: true,
  );
  return buildAppTheme(base, base.colorScheme);
}

void main() {
  testWidgets('收藏条目按 B 站顺序展示进度、标题、分 P 和作者', (tester) async {
    await tester.pumpWidget(_host(onTap: () {}));

    expect(find.text('0:53 / 13:51:05'), findsOneWidget);
    expect(find.text('有声小说《三体》（读客熊猫君）第一部纯享版'), findsOneWidget);
    expect(find.text('03三体｜台球【2007年】'), findsOneWidget);
    expect(find.text('垂钓的渔夫'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains('播放进度 0:53 / 13:51:05') == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏条目支持点击播放和长按管理', (tester) async {
    var played = false;
    var managed = false;
    await tester.pumpWidget(
      _host(onTap: () => played = true, onLongPress: () => managed = true),
    );

    await tester.tap(find.text('03三体｜台球【2007年】'));
    expect(played, isTrue);
    await tester.longPress(find.text('垂钓的渔夫'));
    expect(managed, isTrue);
  });

  testWidgets('收藏条目适配小屏横竖屏、深色模式和大字体', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final config in [
      (size: const Size(375, 812), mode: ThemeMode.light),
      (size: const Size(812, 375), mode: ThemeMode.dark),
    ]) {
      tester.view.physicalSize = config.size;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: config.mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: BiliCollectionListTile(collection: _collection, onTap: _noOp),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

void _noOp() {}
