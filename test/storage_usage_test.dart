import 'dart:io';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:nagomusic/app/services/storage/storage_usage_service.dart';

StorageSection _section(String key, {bool clearable = true}) => StorageSection(
  key: key,
  icon: AppIcons.folder,
  title: key,
  description: key,
  confirmTitle: key,
  confirmMessage: key,
  clearable: clearable,
  resolvePaths: () async => const [],
  clear: () async {},
);

void main() {
  group('StorageUsage', () {
    test('of() returns 0 for an unknown key', () {
      const usage = StorageUsage({'audio': 10});
      expect(usage.of('audio'), 10);
      expect(usage.of('missing'), 0);
    });

    test('total sums every recorded size', () {
      const usage = StorageUsage({'a': 10, 'b': 20, 'c': 0});
      expect(usage.total, 30);
    });

    test('emptyFor seeds every section at 0', () {
      final sections = [_section('a'), _section('b')];
      final usage = StorageUsage.emptyFor(sections);
      expect(usage.of('a'), 0);
      expect(usage.of('b'), 0);
      expect(usage.total, 0);
    });
  });

  group('StorageScan.deletePaths', () {
    test('keep normalizes backslashes vs forward slashes before comparing', () {
      final dir = Directory.systemTemp.createTempSync('storage_scan_test_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final kept = File('${dir.path}/keep.json')..writeAsStringSync('x');
      final removed = File('${dir.path}/remove.json')..writeAsStringSync('x');

      // `keep` 传的是反斜杠形式（Windows 上很常见），而实际路径 dir.path 在这台
      // 机器上可能是正斜杠——如果不先归一化分隔符再比较，这条保留规则会在
      // Windows 上静默失效，把本该留着的文件也删掉。
      final winStyleKeep = kept.path.replaceAll('/', r'\');

      StorageScan.deletePaths([kept.path, removed.path], keep: {winStyleKeep});

      expect(kept.existsSync(), true);
      expect(removed.existsSync(), false);
    });
  });

  group('StorageScan.nameOf', () {
    test('handles forward-slash paths', () {
      expect(StorageScan.nameOf('/a/b/c.txt'), 'c.txt');
    });

    test('handles backslash paths', () {
      expect(StorageScan.nameOf(r'C:\a\b\c.txt'), 'c.txt');
    });

    test('handles mixed separators', () {
      expect(StorageScan.nameOf(r'/a\b/c.txt'), 'c.txt');
    });
  });

  group('StorageSection', () {
    test('defaults clearable to true', () {
      final section = _section('audio');
      expect(section.clearable, true);
    });

    test('can be constructed with clearable: false', () {
      final section = _section('database', clearable: false);
      expect(section.clearable, false);
    });
  });
}
