import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'package:nagomusic/app/utils/multi_select_mixin.dart';

class _Host extends StatefulWidget {
  final bool clearOnEnter;

  const _Host({this.clearOnEnter = true});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host>
    with SignalsMixin, MultiSelectMixin<_Host> {
  @override
  bool get clearSelectionOnEnter => widget.clearOnEnter;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<_HostState> _mount(
  WidgetTester tester, {
  bool clearOnEnter = true,
}) async {
  await tester.pumpWidget(MaterialApp(home: _Host(clearOnEnter: clearOnEnter)));
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('starts empty and not selecting', (tester) async {
    final s = await _mount(tester);
    expect(s.isMultiSelecting, isFalse);
    expect(s.selectedCount, 0);
    expect(s.isAllSelected(0), isFalse);
  });

  testWidgets('toggleSelected adds then removes', (tester) async {
    final s = await _mount(tester);
    s.toggleSelected('a');
    expect(s.isSelected('a'), isTrue);
    s.toggleSelected('a');
    expect(s.isSelected('a'), isFalse);
    expect(s.selectedCount, 0);
  });

  testWidgets('toggleSelectAll selects all then clears', (tester) async {
    final s = await _mount(tester);
    s.toggleSelectAll(['a', 'b', 'c']);
    expect(s.selectedCount, 3);
    expect(s.isAllSelected(3), isTrue);
    s.toggleSelectAll(['a', 'b', 'c']);
    expect(s.selectedCount, 0);
  });

  testWidgets('toggleSelectAll on empty list is a no-op', (tester) async {
    final s = await _mount(tester);
    s.toggleSelected('a');
    s.toggleSelectAll(const <String>[]);
    expect(s.selectedCount, 1, reason: 'must not clear on an empty list');
  });

  testWidgets('clearSelectionOnEnter=true clears both ways', (tester) async {
    final s = await _mount(tester);
    s.toggleSelected('a');
    s.toggleMultiSelect();
    expect(s.isMultiSelecting, isTrue);
    expect(s.selectedCount, 0);
  });

  testWidgets('clearSelectionOnEnter=false keeps selection on enter', (
    tester,
  ) async {
    final s = await _mount(tester, clearOnEnter: false);
    s.toggleSelected('a');
    s.toggleMultiSelect();
    expect(s.isMultiSelecting, isTrue);
    expect(s.selectedCount, 1);

    // Exiting always clears, regardless of the flag.
    s.toggleMultiSelect();
    expect(s.isMultiSelecting, isFalse);
    expect(s.selectedCount, 0);
  });

  testWidgets('exitMultiSelect leaves the mode and clears', (tester) async {
    final s = await _mount(tester);
    s.toggleMultiSelect();
    s.toggleSelected('a');
    s.exitMultiSelect();
    expect(s.isMultiSelecting, isFalse);
    expect(s.selectedCount, 0);
  });

  testWidgets('removeFromSelection drops only the given ids', (tester) async {
    final s = await _mount(tester);
    s.toggleSelectAll(['a', 'b', 'c']);
    s.removeFromSelection(['a', 'c']);
    expect(s.selection, {'b'});
  });

  testWidgets('isAllSelected compares against the given total', (tester) async {
    final s = await _mount(tester);
    s.toggleSelectAll(['a', 'b']);
    expect(s.isAllSelected(2), isTrue);
    expect(s.isAllSelected(3), isFalse);
  });
}
