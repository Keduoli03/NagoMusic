import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_collection_service.dart';
import 'package:nagomusic/app/services/bili/bili_music_service.dart';
import 'package:nagomusic/app/state/song_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

BiliVideoDetail _detail() => const BiliVideoDetail(
  video: BiliVideo(
    bvid: 'BV1collection',
    aid: 42,
    title: '三体有声书合集',
    author: '测试 UP',
    cover: 'https://example.com/cover.jpg',
    durationSec: 1800,
  ),
  parts: [
    BiliPart(cid: 101, index: 1, title: '科学边界', durationSec: 600),
    BiliPart(cid: 102, index: 2, title: '杨冬的遗书', durationSec: 700),
  ],
);

SongEntity _partSong(int cid) => SongEntity(
  id: BiliMusicService.buildSongId('BV1collection', cid),
  title: '第二章',
  artist: '测试 UP',
  uri: BiliMusicService.placeholderUri(
    BiliMusicService.buildSongId('BV1collection', cid),
  ),
  isLocal: false,
  durationMs: 700000,
  sourceId: BiliMusicService.sourceId,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('收藏完整视频详情并在新实例中恢复', () async {
    final service = BiliCollectionService();
    await service.add(_detail());

    expect(service.collections.value, hasLength(1));
    expect(service.collections.value.single.detail.parts, hasLength(2));

    final restored = BiliCollectionService();
    await restored.ensureLoaded();
    expect(restored.collections.value.single.video.title, '三体有声书合集');
    expect(restored.collections.value.single.detail.parts[1].cid, 102);

    service.dispose();
    restored.dispose();
  });

  test('按合集分别恢复上次分 P 和分 P 内进度', () async {
    final service = BiliCollectionService();
    await service.add(_detail());
    await service.recordPlayback(_partSong(102), const Duration(seconds: 83));

    final collection = service.collections.value.single;
    expect(collection.resumeIndex, 1);
    expect(collection.resumePosition, const Duration(seconds: 83));

    final restored = BiliCollectionService();
    await restored.ensureLoaded();
    expect(restored.collections.value.single.resumeIndex, 1);
    expect(
      restored.collections.value.single.resumePosition,
      const Duration(seconds: 83),
    );

    service.dispose();
    restored.dispose();
  });

  test('取消收藏时一并移除该合集进度', () async {
    final service = BiliCollectionService();
    await service.add(_detail());
    await service.recordPlayback(_partSong(101), const Duration(seconds: 12));
    await service.remove('BV1collection');

    expect(service.collections.value, isEmpty);

    final restored = BiliCollectionService();
    await restored.ensureLoaded();
    expect(restored.collections.value, isEmpty);

    service.dispose();
    restored.dispose();
  });
}
