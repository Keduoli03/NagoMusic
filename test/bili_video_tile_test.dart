import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/pages/bili/bili_playback.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, child: child)),
);

void main() {
  testWidgets('长标题完整显示两行而不是截成一行', (tester) async {
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '有声小说《三体》（读客熊猫君） 第一部 纯享版 高音质',
      author: '垂钓的渔夫',
      cover: '',
      durationSec: 49865,
    );
    await tester.pumpWidget(_host(BiliVideoTile(video: video, onTap: () {})));

    final title = tester.widget<Text>(find.text(video.title));
    expect(title.maxLines, 2);
    expect(find.text('垂钓的渔夫'), findsOneWidget);
  });

  testWidgets('封面角标用 时:分:秒，几百小时的合集才读得出来', (tester) async {
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '标题',
      author: 'UP',
      cover: '',
      durationSec: 49865,
    );
    await tester.pumpWidget(_host(BiliVideoTile(video: video, onTap: () {})));
    // 改之前这里是 831:05。
    expect(find.text('13:51:05'), findsOneWidget);
  });

  testWidgets('点击回调触发', (tester) async {
    var tapped = false;
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '标题',
      author: 'UP',
      cover: '',
      durationSec: 100,
    );
    await tester.pumpWidget(
      _host(BiliVideoTile(video: video, onTap: () => tapped = true)),
    );
    await tester.tap(find.text('标题'));
    expect(tapped, isTrue);
  });

  testWidgets('收藏元数据可以分两行完整展示', (tester) async {
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '有声小说《三体》第一部纯享版',
      author: '垂钓的渔夫',
      cover: '',
    );
    const subtitle = '垂钓的渔夫 · 57 个分 P\n上次播放到 P3 0:05';
    await tester.pumpWidget(
      _host(
        BiliVideoTile(
          video: video,
          subtitle: subtitle,
          subtitleMaxLines: 2,
          onTap: () {},
        ),
      ),
    );

    final metadata = tester.widget<Text>(find.text(subtitle));
    expect(metadata.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按收藏行触发管理操作而不播放', (tester) async {
    var played = false;
    var managed = false;
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '标题',
      author: 'UP',
      cover: '',
    );
    await tester.pumpWidget(
      _host(
        BiliVideoTile(
          video: video,
          onTap: () => played = true,
          onLongPress: () => managed = true,
        ),
      ),
    );

    await tester.longPress(find.text('标题'));
    expect(managed, isTrue);
    expect(played, isFalse);
  });

  testWidgets('点击收藏按钮不会误触发视频播放', (tester) async {
    var played = false;
    var favorited = false;
    const video = BiliVideo(
      bvid: 'BV1',
      aid: 1,
      title: '标题',
      author: 'UP',
      cover: '',
    );
    await tester.pumpWidget(
      _host(
        BiliVideoTile(
          video: video,
          onTap: () => played = true,
          trailing: IconButton(
            tooltip: '收藏整个视频',
            icon: const Icon(AppIcons.bookmark),
            onPressed: () => favorited = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('收藏整个视频'));
    expect(favorited, isTrue);
    expect(played, isFalse);
  });
}
