import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/components/common/sheet_panels.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:nagomusic/pages/bili/bili_playback.dart';

/// 造一个「每个分 P 的名字都等于视频标题」的有声书合集 —— 这正是当初撑爆布局的形状。
BiliVideoDetail _audiobook(int partCount) {
  const title = '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质';
  return BiliVideoDetail(
    video: const BiliVideo(
      bvid: 'BV1xx411c7mD',
      aid: 1,
      title: title,
      author: '读客熊猫君',
      cover: '',
      durationSec: 1200,
    ),
    parts: List.generate(
      partCount,
      (i) => BiliPart(
        cid: 1000 + i,
        index: i + 1,
        title: title,
        durationSec: 600 + i,
      ),
    ),
  );
}

Widget _host(Widget sheet) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        // 对应 showModalBottomSheet 传的 maxHeight 封顶。
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 432),
          child: sheet,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('57 个分 P 不会撑爆面板', (tester) async {
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: _audiobook(57),
          onPlayAll: () {},
          onPlayPart: (_) {},
        ),
      ),
    );
    // 溢出会以 FlutterError 的形式记录在 takeException 里。
    expect(tester.takeException(), isNull);
    expect(find.text('选择分 P · 57 个'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
  });

  testWidgets('分 P 面板初始为七成高度并可上拉展开到全屏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliPartPickerDraggableSheet(
            detail: _audiobook(57),
            onPlayAll: () {},
            onPlayPart: (_) {},
          ),
        ),
      ),
    );

    final draggable = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(draggable.initialChildSize, 0.72);
    expect(draggable.maxChildSize, 1);

    final initialHeight = tester.getSize(find.byType(AppSheetPanel)).height;
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final expandedHeight = tester.getSize(find.byType(AppSheetPanel)).height;

    expect(expandedHeight, greaterThan(initialHeight));
    expect(expandedHeight, closeTo(600, 1));
  });

  testWidgets('已收藏合集显示的是取消收藏，不是再收藏一次', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliPartPickerDraggableSheet(
            detail: _audiobook(10),
            initiallyFavorite: true,
            onToggleFavorite: () async => false,
            onPlayAll: () {},
            onPlayPart: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('读客熊猫君'), findsOneWidget);
    // 已收藏时按钮仍然在，但语义反过来：实心星 + 「取消收藏」。
    expect(find.byTooltip('收藏整个视频'), findsNothing);
    expect(find.byTooltip('取消收藏整个视频'), findsOneWidget);
    expect(find.byIcon(AppIconsFilled.star), findsOneWidget);
    expect(find.byIcon(AppIcons.star), findsNothing);
  });

  testWidgets('未收藏视频仍可从分 P 面板收藏', (tester) async {
    var favorite = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiliPartPickerDraggableSheet(
            detail: _audiobook(10),
            onToggleFavorite: () async {
              favorite = true;
              return true;
            },
            onPlayAll: () {},
            onPlayPart: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('收藏整个视频'));
    await tester.pump();

    expect(favorite, isTrue);
    expect(find.byTooltip('收藏整个视频'), findsNothing);
  });

  testWidgets('分 P 名与视频标题相同时退回 P1/P2 而不是刷屏', (tester) async {
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: _audiobook(57),
          onPlayAll: () {},
          onPlayPart: (_) {},
        ),
      ),
    );
    // 标题只在顶部那行出现一次，列表里是 P1/P2…，而且每行只出现一次（不是「P3 P3」）。
    expect(find.textContaining('有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
  });

  testWidgets('分 P 有独立名字时只显示分 P 名，序号放在行首', (tester) async {
    final detail = BiliVideoDetail(
      video: const BiliVideo(
        bvid: 'BV1',
        aid: 1,
        title: '专辑合集',
        author: 'UP',
        cover: '',
      ),
      parts: const [
        BiliPart(cid: 1, index: 1, title: '晴天', durationSec: 269),
        BiliPart(cid: 2, index: 2, title: '稻香', durationSec: 223),
      ],
    );
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: detail,
          onPlayAll: () {},
          onPlayPart: (_) {},
        ),
      ),
    );
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('稻香'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('3:43'), findsOneWidget);
  });

  testWidgets('点某个分 P 回调对应下标', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: _audiobook(10),
          onPlayAll: () {},
          onPlayPart: (index) => tapped = index,
        ),
      ),
    );
    await tester.tap(find.text('P3'));
    expect(tapped, 2);
  });

  testWidgets('有合集进度时显示继续播放入口并触发回调', (tester) async {
    var resumed = false;
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: _audiobook(10),
          resumePartIndex: 2,
          resumePosition: const Duration(minutes: 4, seconds: 21),
          onResume: () => resumed = true,
          onPlayAll: () {},
          onPlayPart: (_) {},
        ),
      ),
    );

    expect(find.text('继续 P3 · 4:21'), findsOneWidget);
    await tester.tap(find.text('继续 P3 · 4:21'));
    expect(resumed, isTrue);
  });

  testWidgets('分 P 列表在紧凑头部后立即开始', (tester) async {
    await tester.pumpWidget(
      _host(
        BiliPartPickerSheet(
          detail: _audiobook(57),
          resumePartIndex: 2,
          resumePosition: const Duration(seconds: 5),
          onResume: () {},
          onPlayAll: () {},
          onPlayPart: (_) {},
        ),
      ),
    );

    final panelTop = tester.getTopLeft(find.byType(AppSheetPanel)).dy;
    final listTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(listTop - panelTop, lessThan(150));
  });

  group('时长格式', () {
    test('不足一小时用 分:秒', () {
      expect(formatBiliDuration(0), '');
      expect(formatBiliDuration(65), '1:05');
      expect(formatBiliDuration(3599), '59:59');
    });

    test('超过一小时带上小时位', () {
      // 有声书合集常见的几百小时，原来会格式化成 831:05 这种读不出来的数字。
      expect(formatBiliDuration(3600), '1:00:00');
      expect(formatBiliDuration(49865), '13:51:05');
    });
  });
}
