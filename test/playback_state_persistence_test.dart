import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nagomusic/app/services/player/playback_state_persistence.dart';
import 'package:nagomusic/app/state/player_state.dart';
import 'package:nagomusic/app/state/song_state.dart';

PlaybackStatePersistence _persistence({
  required List<SongEntity> queue,
  required int index,
  required PlaybackMode mode,
  required bool playing,
  required String? songId,
  Duration position = Duration.zero,
}) => PlaybackStatePersistence(
  isRestoring: () => false,
  isPlaying: () => playing,
  queue: () => queue,
  currentIndex: () => index,
  mode: () => mode,
  currentSongId: () => songId,
  positionForPersistence: () => position,
);

SongEntity _song(String id) => SongEntity(
  id: id,
  title: '标题',
  artist: '歌手',
  uri: 'http://x/$id',
  isLocal: false,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persist 后 read 能还原同一会话', () async {
    final queue = [_song('s1'), _song('s2')];
    final p = _persistence(
      queue: queue,
      index: 1,
      mode: PlaybackMode.shuffle,
      playing: true,
      songId: 's2',
      position: const Duration(seconds: 42),
    );
    await p.persistNow();

    final restored = await p.read();
    expect(restored, isNotNull);
    expect(restored!.queue.map((s) => s.id).toList(), ['s1', 's2']);
    expect(restored.index, 1);
    expect(restored.songId, 's2');
    expect(restored.position, const Duration(seconds: 42));
    expect(restored.mode, PlaybackMode.shuffle);
    expect(restored.wasPlaying, isTrue);
  });

  test('队列为空时 persist 清掉持久化状态', () async {
    final p = _persistence(
      queue: [],
      index: -1,
      mode: PlaybackMode.loop,
      playing: false,
      songId: null,
    );
    await p.persistNow();
    expect(await p.read(), isNull);
  });

  test('prefs key 钉死 —— 改名会让所有用户丢掉续播位置', () {
    expect(PlaybackStatePersistence.prefsQueueKey, 'playback_queue_v1');
    expect(PlaybackStatePersistence.prefsIndexKey, 'playback_index_v1');
    expect(PlaybackStatePersistence.prefsPositionKey, 'playback_position_v1');
    expect(PlaybackStatePersistence.prefsModeKey, 'playback_mode_v1');
    expect(
      PlaybackStatePersistence.prefsWasPlayingKey,
      'playback_was_playing_v1',
    );
    expect(PlaybackStatePersistence.prefsSongIdKey, 'playback_song_id_v1');
  });

  test('modeFromString 解析播放模式', () {
    final p = _persistence(
      queue: [],
      index: 0,
      mode: PlaybackMode.loop,
      playing: false,
      songId: null,
    );
    expect(p.modeFromString('shuffle'), PlaybackMode.shuffle);
    expect(p.modeFromString('loop'), PlaybackMode.loop);
    expect(p.modeFromString('single'), PlaybackMode.single);
    expect(p.modeFromString('junk'), isNull);
  });
}
