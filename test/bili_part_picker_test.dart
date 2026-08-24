import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_models.dart';
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
    expect(find.text('播放全部 57 个分 P'), findsOneWidget);
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
    expect(
      find.text('有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质'),
      findsOneWidget,
    );
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

