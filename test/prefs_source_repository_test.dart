import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/services/navidrome/navidrome_source_repository.dart';
import 'package:nagomusic/app/services/webdav/webdav_source_repository.dart';

const _navidrome = NavidromeSource(
  id: 'navidrome-1',
  name: 'Home',
  endpoint: 'https://music.example.com',
  username: 'alice',
  password: 'secret',
  salt: 'abc123',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 两个仓库都是进程级单例，活过整个测试文件；重置 SharedPreferences 的
    // mock 后备存储换不掉仓库自己的内存缓存，不清的话这个测试会读到上一个
    // 测试留下的数据。
    NavidromeSourceRepository.instance.resetCacheForTest();
    WebDavSourceRepository.instance.resetCacheForTest();
  });

  group('shared prefs-backed CRUD', () {
    test('round-trips navidrome sources', () async {
      final repo = NavidromeSourceRepository.instance;
      expect(await repo.loadSources(), isEmpty);

      await repo.upsert(_navidrome);
      final loaded = await repo.loadSources();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'navidrome-1');
      expect(loaded.single.username, 'alice');
    });

    test('upsert replaces an existing entry rather than appending', () async {
      final repo = NavidromeSourceRepository.instance;
      await repo.upsert(_navidrome);
      await repo.upsert(_navidrome.copyWith(name: 'Renamed'));

      final loaded = await repo.loadSources();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'Renamed');
    });

    test('removeById drops only the matching entry', () async {
      final repo = NavidromeSourceRepository.instance;
      await repo.upsert(_navidrome);
      await repo.upsert(_navidrome.copyWith(id: 'navidrome-2'));

      await repo.removeById('navidrome-1');
      final loaded = await repo.loadSources();
      expect(loaded.map((e) => e.id), ['navidrome-2']);
    });

    test('malformed stored json degrades to an empty list', () async {
      SharedPreferences.setMockInitialValues({
        'navidrome_sources_v1': 'not json at all',
      });
      expect(await NavidromeSourceRepository.instance.loadSources(), isEmpty);
    });

    test('entries without an id are discarded', () async {
      SharedPreferences.setMockInitialValues({
        'navidrome_sources_v1': '[{"name":"orphan"}]',
      });
      expect(await NavidromeSourceRepository.instance.loadSources(), isEmpty);
    });

    test('webdav and navidrome use separate storage keys', () async {
      await NavidromeSourceRepository.instance.upsert(_navidrome);
      expect(await WebDavSourceRepository.instance.loadSources(), isEmpty);
    });

    test('newId carries the per-source prefix', () {
      expect(
        NavidromeSourceRepository.instance.newId(),
        startsWith('navidrome-'),
      );
      expect(WebDavSourceRepository.instance.newId(), startsWith('webdav-'));
    });
  });

  group('in-memory cache', () {
    test('loadSources 只读一次 prefs，后续命中缓存', () async {
      final repo = NavidromeSourceRepository.instance;
      await repo.upsert(_navidrome);
      final first = await repo.loadSources();

      // 绕过仓库直接改后备存储，模拟"缓存之外还有别的东西动了 prefs"——
      // 正常情况下这不会发生（都走 upsert/removeById），这里只是用来证明
      // loadSources 命中的是内存缓存，而不是每次都重新解一遍 JSON。
      SharedPreferences.setMockInitialValues({'navidrome_sources_v1': '[]'});

      final second = await repo.loadSources();
      expect(second, same(first));
      expect(second, hasLength(1));
    });

    test('upsert/removeById 之后缓存立刻反映新值，不是下一次才生效', () async {
      final repo = WebDavSourceRepository.instance;
      await repo.upsert(
        const WebDavSource(
          id: 'webdav-1',
          name: 'Home',
          endpoint: 'https://dav.example.com',
          username: 'bob',
          password: 'pw',
          path: '/',
        ),
      );
      expect(await repo.loadSources(), hasLength(1));

      await repo.removeById('webdav-1');
      expect(await repo.loadSources(), isEmpty);
    });

    test('resetCacheForTest 之后重新从 prefs 读取', () async {
      final repo = NavidromeSourceRepository.instance;
      await repo.upsert(_navidrome);
      expect(await repo.loadSources(), hasLength(1));

      SharedPreferences.setMockInitialValues({});
      repo.resetCacheForTest();
      expect(await repo.loadSources(), isEmpty);
    });
  });
}
