import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/services/playlists_service.dart';
import 'package:nagomusic/pages/library/playlists_sort_controller.dart';

PlaylistEntity _p(
  String id,
  String name, {
  bool isFavorite = false,
  int createdAtMs = 0,
  List<String> songIds = const [],
}) {
  return PlaylistEntity(
    id: id,
    name: name,
    songIds: songIds,
    createdAtMs: createdAtMs,
    isFavorite: isFavorite,
  );
}

void main() {
  group('PlaylistsSortController.sortPlaylists', () {
    test('custom 模式原样返回，不做任何排序', () {
      final playlists = [_p('2', 'b'), _p('1', 'a')];
      final result = PlaylistsSortController.sortPlaylists(
        playlists: playlists,
        sortMode: 'custom',
        ascending: true,
      );
      expect(result, same(playlists));
    });

    test('按名称排序时"我喜欢"始终置顶', () {
      final favorite = _p('fav', '我喜欢', isFavorite: true);
      final playlists = [_p('2', 'b'), favorite, _p('1', 'a')];
      final result = PlaylistsSortController.sortPlaylists(
        playlists: playlists,
        sortMode: 'name',
        ascending: true,
      );
      expect(result.map((p) => p.id), ['fav', '1', '2']);
    });

    test('按歌曲数量降序排序', () {
      final playlists = [
        _p('1', 'a', songIds: ['s1']),
        _p('2', 'b', songIds: ['s1', 's2', 's3']),
        _p('3', 'c', songIds: ['s1', 's2']),
      ];
      final result = PlaylistsSortController.sortPlaylists(
        playlists: playlists,
        sortMode: 'count',
        ascending: false,
      );
      expect(result.map((p) => p.id), ['2', '3', '1']);
    });

    test('按创建时间升序排序是默认分支', () {
      final playlists = [
        _p('1', 'a', createdAtMs: 300),
        _p('2', 'b', createdAtMs: 100),
        _p('3', 'c', createdAtMs: 200),
      ];
      final result = PlaylistsSortController.sortPlaylists(
        playlists: playlists,
        sortMode: 'recent',
        ascending: true,
      );
      expect(result.map((p) => p.id), ['2', '3', '1']);
    });
  });

  group('PlaylistsSortController prefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('没存过偏好时默认 custom + 升序', () async {
      final controller = PlaylistsSortController();
      final prefs = await controller.loadPrefs();
      expect(prefs.sortMode, 'custom');
      expect(prefs.ascending, isTrue);
    });

    test('save 之后 load 能读回同样的偏好', () async {
      final controller = PlaylistsSortController();
      await controller.savePrefs(sortMode: 'name', ascending: false);
      final prefs = await controller.loadPrefs();
      expect(prefs.sortMode, 'name');
      expect(prefs.ascending, isFalse);
    });

    test('存了空字符串的排序模式时退回 custom', () async {
      SharedPreferences.setMockInitialValues({'playlists_sort_mode_v1': '   '});
      final controller = PlaylistsSortController();
      final prefs = await controller.loadPrefs();
      expect(prefs.sortMode, 'custom');
    });
  });
}
