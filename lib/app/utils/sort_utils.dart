/// 列表分组排序的共用逻辑。
library;

/// 排序 [items]，并把「未知XX」分组固定放在最前。
///
/// 顺序与各页面此前的内联实现一致：先按 [compare] 升序排，
/// [ascending] 为 false 时整体反转，最后再把满足 [isUnknown] 的项移到首位
/// ——即「未知」项不参与升降序，始终置顶。
///
/// [isUnknown] 为 null 时跳过置顶步骤（例如按年份排序时）。
void sortGroupsWithUnknownFirst<T>(
  List<T> items, {
  required int Function(T a, T b) compare,
  required bool ascending,
  bool Function(T item)? isUnknown,
}) {
  items.sort(compare);
  if (!ascending) {
    items.replaceRange(0, items.length, items.reversed.toList());
  }
  if (isUnknown == null) return;
  final idx = items.indexWhere(isUnknown);
  if (idx > 0) {
    items.insert(0, items.removeAt(idx));
  }
}
