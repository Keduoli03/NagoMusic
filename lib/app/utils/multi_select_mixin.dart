import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// 列表页「多选模式」的共用状态与操作。
///
/// 各列表页此前都各自声明 `_multiSelect` / `_selectedIds` 两个 signal，
/// 并重复实现进入/退出多选、全选、单项切换等逻辑；这里统一持有。
///
/// 使用页面需要同时 `with SignalsMixin`（本 mixin 依赖 [createSignal]）。
mixin MultiSelectMixin<T extends StatefulWidget> on State<T>, SignalsMixin<T> {
  late final multiSelect = createSignal(false);
  late final selectedIds = createSignal<Set<String>>(<String>{});

  /// 进入多选模式时是否也清空已选中项。
  ///
  /// 默认 true（进入和退出都清空）；若页面希望保留进入前的选中状态，覆写为 false。
  bool get clearSelectionOnEnter => true;

  bool get isMultiSelecting => multiSelect.value;

  Set<String> get selection => selectedIds.value;

  int get selectedCount => selectedIds.value.length;

  bool isSelected(String id) => selectedIds.value.contains(id);

  /// 相对 [total] 是否已全选（[total] 为 0 时返回 false）。
  bool isAllSelected(int total) =>
      total > 0 && selectedIds.value.length == total;

  void clearSelection() {
    selectedIds.value = <String>{};
  }

  void toggleMultiSelect() {
    final entering = !multiSelect.value;
    multiSelect.value = entering;
    if (!entering || clearSelectionOnEnter) {
      clearSelection();
    }
  }

  /// 退出多选模式并清空选中项（批量操作完成后调用）。
  void exitMultiSelect() {
    multiSelect.value = false;
    clearSelection();
  }

  void toggleSelected(String id) {
    final next = Set<String>.from(selectedIds.value);
    if (!next.remove(id)) {
      next.add(id);
    }
    selectedIds.value = next;
  }

  void removeFromSelection(Iterable<String> ids) {
    selectedIds.value = Set<String>.from(selectedIds.value)..removeAll(ids);
  }

  /// 全选 / 取消全选：已全选时清空，否则选中 [ids] 全部。
  void toggleSelectAll(Iterable<String> ids) {
    final all = ids.toList(growable: false);
    if (all.isEmpty) return;
    if (selectedIds.value.length == all.length) {
      clearSelection();
      return;
    }
    selectedIds.value = all.toSet();
  }
}
