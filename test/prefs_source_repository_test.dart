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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
}
