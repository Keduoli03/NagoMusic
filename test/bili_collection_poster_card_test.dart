import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_collection_service.dart';
import 'package:nagomusic/app/theme/app_theme.dart';
import 'package:nagomusic/pages/bili/widgets/bili_collection_poster_card.dart';

const _collection = BiliVideoCollection(
  detail: BiliVideoDetail(
    video: BiliVideo(
      bvid: 'BV1poster',
      aid: 1,
      title: '适合通勤的爵士合集',
      author: '测试 UP',
      cover: '',
      durationSec: 600,
    ),
    parts: [BiliPart(cid: 10, index: 1, title: '第一首', durationSec: 600)],
  ),
  addedAtMs: 1,
);

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
  testWidgets('收藏海报展示视频信息并可直接打开', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliCollectionPosterCard(
            collection: _collection,
            onTap: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('适合通勤的爵士合集'), findsOneWidget);
    expect(find.text('测试 UP · 单 P'), findsOneWidget);
    expect(tester.getSize(find.byType(BiliCollectionPosterCard)).width, 176);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '播放收藏视频：适合通勤的爵士合集',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(BiliCollectionPosterCard));
    expect(opened, isTrue);
  });

  testWidgets('收藏海报适配小屏横竖屏、深色模式和大字体', (tester) async {
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
            body: Align(
              alignment: Alignment.topLeft,
              child: BiliCollectionPosterCard(
                collection: _collection,
                onTap: _noOp,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

void _noOp() {}
