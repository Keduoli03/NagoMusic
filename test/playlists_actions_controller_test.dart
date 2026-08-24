import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/services/playlists_service.dart';
import 'package:nagomusic/pages/library/playlists_actions_controller.dart';

PlaylistEntity _p(String id, {bool isFavorite = false}) {
  return PlaylistEntity(
    id: id,
    name: id,
    songIds: const [],
    createdAtMs: 0,
    isFavorite: isFavorite,
  );
}

void main() {
  group('PlaylistsActionsController.reorderList', () {
    test('把拖拽的歌单移动到目标位置', () {
      final current = [_p('a'), _p('b'), _p('c')];
      final result = PlaylistsActionsController.reorderList(
        current: current,
        oldIndex: 0,
        newIndex: 2,
      );
      expect(result?.map((p) => p.id), ['b', 'a', 'c']);
    });

    test('"我喜欢"歌单不可被拖动，直接返回 null', () {
      final current = [_p('fav', isFavorite: true), _p('a'), _p('b')];
      final result = PlaylistsActionsController.reorderList(
        current: current,
        oldIndex: 0,
        newIndex: 2,
      );
      expect(result, isNull);
    });

    test('把某个歌单拖到"我喜欢"前面后，"我喜欢"仍会被拉回第一位', () {
      final current = [_p('fav', isFavorite: true), _p('a'), _p('b')];
      final result = PlaylistsActionsController.reorderList(
        current: current,
        oldIndex: 2,
        newIndex: 0,
      );
      expect(result?.map((p) => p.id), ['fav', 'b', 'a']);
    });

    test('oldIndex 越界时返回 null', () {
      final current = [_p('a')];
      expect(
        PlaylistsActionsController.reorderList(
          current: current,
          oldIndex: 5,
          newIndex: 0,
        ),
        isNull,
      );
    });

    test('newIndex 越界时返回 null', () {
      final current = [_p('a'), _p('b')];
      expect(
        PlaylistsActionsController.reorderList(
          current: current,
          oldIndex: 0,
          newIndex: 5,
        ),
        isNull,
      );
    });
  });
}
