import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/app/utils/sort_utils.dart';

int _byName(String a, String b) => a.compareTo(b);

void main() {
  group('sortGroupsWithUnknownFirst', () {
    test('sorts ascending', () {
      final items = ['c', 'a', 'b'];
      sortGroupsWithUnknownFirst(items, compare: _byName, ascending: true);
      expect(items, ['a', 'b', 'c']);
    });

    test('reverses for descending', () {
      final items = ['c', 'a', 'b'];
      sortGroupsWithUnknownFirst(items, compare: _byName, ascending: false);
      expect(items, ['c', 'b', 'a']);
    });

    test('pins the unknown entry first, ascending', () {
      final items = ['b', '未知专辑', 'a'];
      sortGroupsWithUnknownFirst(
        items,
        compare: _byName,
        ascending: true,
        isUnknown: (e) => e == '未知专辑',
      );
      expect(items, ['未知专辑', 'a', 'b']);
    });

    test('pins the unknown entry first even when descending', () {
      final items = ['b', '未知专辑', 'a'];
      sortGroupsWithUnknownFirst(
        items,
        compare: _byName,
        ascending: false,
        isUnknown: (e) => e == '未知专辑',
      );
      expect(items.first, '未知专辑');
      expect(items.sublist(1), ['b', 'a']);
    });

    test('no isUnknown leaves ordering untouched', () {
      final items = ['b', '未知专辑', 'a'];
      sortGroupsWithUnknownFirst(items, compare: _byName, ascending: true);
      expect(items, ['a', 'b', '未知专辑']);
    });

    test('handles a missing unknown entry', () {
      final items = ['b', 'a'];
      sortGroupsWithUnknownFirst(
        items,
        compare: _byName,
        ascending: true,
        isUnknown: (e) => e == '未知专辑',
      );
      expect(items, ['a', 'b']);
    });

    test('handles the unknown entry already being first', () {
      final items = ['未知专辑', 'b', 'a'];
      sortGroupsWithUnknownFirst(
        items,
        compare: _byName,
        ascending: true,
        isUnknown: (e) => e == '未知专辑',
      );
      expect(items, ['未知专辑', 'a', 'b']);
    });

    test('empty and single-element lists are safe', () {
      final empty = <String>[];
      sortGroupsWithUnknownFirst(empty, compare: _byName, ascending: true);
      expect(empty, isEmpty);

      final single = ['a'];
      sortGroupsWithUnknownFirst(
        single,
        compare: _byName,
        ascending: false,
        isUnknown: (e) => e == 'a',
      );
      expect(single, ['a']);
    });
  });
}
