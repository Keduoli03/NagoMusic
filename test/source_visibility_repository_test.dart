import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nagomusic/app/services/source_visibility_repository.dart';

void main() {
  final repository = SourceVisibilityRepository.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository.resetCacheForTest();
  });

  test('sources are enabled by default', () async {
    expect(await repository.isEnabled('local'), isTrue);
    expect(await repository.isEnabled('webdav-1'), isTrue);
  });

  test('disabled state persists and can be enabled again', () async {
    await repository.setEnabled('webdav-1', false);
    expect(await repository.isEnabled('webdav-1'), isFalse);

    repository.resetCacheForTest();
    expect(await repository.isEnabled('webdav-1'), isFalse);

    await repository.setEnabled('webdav-1', true);
    expect(await repository.isEnabled('webdav-1'), isTrue);
  });

  test('filterEnabled keeps only enabled sources', () async {
    await repository.setEnabled('navidrome-2', false);

    final result = await repository.filterEnabled([
      'local',
      'navidrome-1',
      'navidrome-2',
    ], (sourceId) => sourceId);

    expect(result, ['local', 'navidrome-1']);
  });

  test('rapid updates are persisted in call order', () async {
    final disable = repository.setEnabled('webdav-1', false);
    final enable = repository.setEnabled('webdav-1', true);

    await Future.wait([disable, enable]);
    repository.resetCacheForTest();

    expect(await repository.isEnabled('webdav-1'), isTrue);
  });
}
