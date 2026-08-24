import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/services/bili/bili_prefs.dart';

class _Folder {
  final int id;
  const _Folder(this.id);
}

void main() {
  const folders = [_Folder(1), _Folder(2), _Folder(3)];
  int idOf(_Folder f) => f.id;

  group('收藏夹显示筛选', () {
    test('没配置过时显示全部，而不是一个都不显示', () {
      final result = BiliPrefs.filterFolders(folders, const {}, idOf);
      expect(result.length, 3);
    });

    test('配置过就只显示勾选的', () {
      final result = BiliPrefs.filterFolders(folders, const {1, 3}, idOf);
      expect(result.map(idOf), [1, 3]);
    });

    test('勾选的收藏夹已被删除时退回全部显示，避免打开一片空白', () {
      final result = BiliPrefs.filterFolders(folders, const {99}, idOf);
      expect(result.length, 3);
    });
  });
}
