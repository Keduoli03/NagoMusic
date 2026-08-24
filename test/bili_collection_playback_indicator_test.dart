import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/state/song_state.dart';
import 'package:nagomusic/pages/bili/widgets/bili_collection_playback_indicator.dart';

void main() {
  test('matches only a Bili song from the same video collection', () {
    final song = SongEntity(
      id: 'bili::BV1test-123',
      title: 'P1',
      artist: 'UP',
      uri: 'bili://BV1test/123',
      isLocal: false,
      sourceId: 'bili',
    );

    expect(
      BiliCollectionPlaybackIndicator.matchesCollection(song, 'BV1test'),
      isTrue,
    );
    expect(
      BiliCollectionPlaybackIndicator.matchesCollection(song, 'BV1other'),
      isFalse,
    );
  });
}
