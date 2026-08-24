import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/pages/bili/bili_fav_folder_page.dart';

void main() {
  testWidgets('收藏夹加载后展示视频，点击视频走播放入口', (tester) async {
    const folder = BiliFavFolder(id: 7, title: '稍后再听', mediaCount: 2);
    const videos = [
      BiliVideo(
        bvid: 'BV1first',
        aid: 1,
        title: '第一个视频',
        author: 'UP 甲',
        cover: '',
        durationSec: 120,
      ),
      BiliVideo(
        bvid: 'BV1second',
        aid: 2,
        title: '第二个视频',
        author: 'UP 乙',
        cover: '',
        durationSec: 180,
      ),
    ];
    BiliVideo? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: BiliFavFolderPage(
          folder: folder,
          loadResources: (_) async => videos,
          openVideo: (context, video) async => opened = video,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('稍后再听'), findsOneWidget);
    expect(find.text('第一个视频'), findsOneWidget);
    expect(find.text('第二个视频'), findsOneWidget);

    await tester.tap(find.text('第二个视频'));
    expect(opened?.bvid, 'BV1second');
  });
}
