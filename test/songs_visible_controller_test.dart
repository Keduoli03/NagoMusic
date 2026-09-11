import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/state/song_state.dart';
import 'package:nagomusic/pages/songs/songs_visible_controller.dart';

SongEntity _song(String id, int? fileModifiedMs) {
  return SongEntity(
    id: id,
    title: id,
    artist: 'artist',
    isLocal: true,
    fileModifiedMs: fileModifiedMs,
  );
}

void main() {
  test('sorts songs by file modification time in either direction', () async {
    final controller = SongsVisibleController();
    final songs = [
      _song('newest', 300),
      _song('unknown', null),
      _song('oldest', 100),
    ];

    final ascending = await controller.buildVisibleSongs(
      songs: songs,
      sourceFilter: 'all',
      sortKey: 'modifiedTime',
      ascending: true,
      currentMaxCount: songs.length,
    );
    final descending = await controller.buildVisibleSongs(
      songs: songs,
      sourceFilter: 'all',
      sortKey: 'modifiedTime',
      ascending: false,
      currentMaxCount: songs.length,
    );

    expect(ascending.allVisible.map((song) => song.id), [
      'unknown',
      'oldest',
      'newest',
    ]);
    expect(descending.allVisible.map((song) => song.id), [
      'newest',
      'oldest',
      'unknown',
    ]);
  });
}
