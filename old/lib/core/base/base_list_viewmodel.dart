import 'base_viewmodel.dart';

/// 列表基础 ViewModel（轻量版）
///
/// - 提供分页/刷新/加载更多的最小实现
abstract class BaseListViewModel<T> extends BaseViewModel {
  final List<T> items = <T>[];
  int page = 1;
  int pageSize = 20;
  bool hasMore = true;
  bool isLoadingMore = false;
  bool loadMoreFailed = false;
  Object? loadMoreError;

  /// 子类必须实现：拉取一页数据（函数级注释）
  Future<List<T>> fetchPage({required int page, required int pageSize});

  /// 初始化加载（函数级注释）
  @override
  Future<void> onInit() async {
    super.onInit();
    await loadData();
  }

  /// 首屏加载（函数级注释）
  Future<void> loadData() async {
    setState(ViewState.loading);
    page = 1;
    hasMore = true;
    try {
      final list = await fetchPage(page: page, pageSize: pageSize);
      if (isDisposed) return; // 异步完成后检查是否已释放

      items
        ..clear()
        ..addAll(list);
      _configHasMore(list);
      setState(ViewState.success);
    } catch (e) {
      if (isDisposed) return; // 捕获异常后也需检查
      setState(ViewState.error, error: e.toString());
    }
  }

  /// 下拉刷新（函数级注释）
  @override
  Future<void> refreshData() async {
    if (isRefreshing || isDisposed) return; // 添加释放检查
    setRefreshing(true);
    final old = state;
    try {
      page = 1;
      hasMore = true;
      final list = await fetchPage(page: page, pageSize: pageSize);
      if (isDisposed) return; // 异步完成后检查是否已释放

      items
        ..clear()
        ..addAll(list);
      _configHasMore(list);
      setState(ViewState.success);
    } catch (_) {
      if (isDisposed) return; // 捕获异常后也需检查
      // 刷新失败回退原状态
      setState(old);
    } finally {
      setRefreshing(false);
    }
  }

  /// 加载更多（函数级注释）
  Future<void> loadMore() async {
    if (!hasMore || isLoadingMore || isDisposed) return; // 添加释放检查
    isLoadingMore = true;
    loadMoreFailed = false;
    loadMoreError = null;
    try {
      final next = page + 1;
      final list = await fetchPage(page: next, pageSize: pageSize);
      if (isDisposed) return; // 异步完成后检查是否已释放

      if (list.isNotEmpty) {
        items.addAll(list);
        page = next;
      }
      _configHasMore(list);
    } catch (e) {
      if (isDisposed) return; // 捕获异常后也需检查
      loadMoreFailed = true;
      loadMoreError = e;
    } finally {
      isLoadingMore = false;
      notifyDataChange();
    }
  }

  /// 重置分页（函数级注释）
  void resetPaging({int initialPage = 1, int pageSize = 20}) {
    page = initialPage;
    this.pageSize = pageSize;
    hasMore = true;
    items.clear();
    loadMoreFailed = false;
    loadMoreError = null;
    setState(ViewState.idle);
  }

  /// 计算是否还有更多（函数级注释）
  void _configHasMore(List<T> data) {
    hasMore = data.length >= pageSize;
    loadMoreFailed = false;
    loadMoreError = null;
  }

  /// 清空列表
  void clearItems() {
    items.clear();
    page = 1;
    hasMore = true;
    notifyDataChange();
  }

  /// 数据操作：添加（函数级注释）
  void addItem(T item) {
    items.add(item);
    notifyDataChange();
  }

  /// 数据操作：移除（函数级注释）
  void removeItem(T item) {
    items.remove(item);
    notifyDataChange();
  }

  /// 数据操作：更新（函数级注释）
  void updateItem(int index, T item) {
    if (index >= 0 && index < items.length) {
      items[index] = item;
      notifyDataChange();
    }
  }

  /// 批量操作：批量添加
  void addItems(List<T> newItems) {
    if (newItems.isEmpty) return;
    items.addAll(newItems);
    notifyDataChange();
  }

  /// 批量操作：批量移除
  void removeItems(List<T> targets) {
    if (targets.isEmpty) return;
    items.removeWhere((item) => targets.contains(item));
    notifyDataChange();
  }

  /// 批量操作：替换整个列表
  void replaceItems(List<T> newItems) {
    items
      ..clear()
      ..addAll(newItems);
    notifyDataChange();
  }
}
