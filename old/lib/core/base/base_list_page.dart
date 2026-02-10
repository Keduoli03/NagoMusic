import 'package:flutter/material.dart';

import '../theme/index.dart';
import 'base_list_viewmodel.dart';
import 'base_page.dart';

/// 列表页面基类：在 BasePage 基础上扩展列表体与触底加载能力
abstract class BaseListPage<T, VM extends BaseListViewModel<T>>
    extends BasePage<VM> {
  /// 构造函数
  const BaseListPage({super.key});

  @override
  State<BaseListPage<T, VM>> createState();
}

/// 列表页面State基类 - 用户继承此类
abstract class BaseListPageState<T, VM extends BaseListViewModel<T>,
    W extends BaseListPage<T, VM>> extends BasePageState<VM, W> {
  late final ScrollController _controller;

  // ==================== 子类必须实现 ====================

  /// 渲染单个条目
  Widget buildItem(BuildContext context, T item, int index);

  // ==================== 可选重写的列表配置 ====================

  /// 构建列表容器（可选）
  ///
  /// **返回 null**：使用默认 ListView.builder
  ///
  /// **自定义列表容器**：
  /// - 请使用 `scrollController` 以支持上拉加载
  /// - 原生刷新功能仍然生效（除非 `enableRefresh = false`）
  ///
  /// 示例：
  /// ```dart
  /// @override
  /// Widget buildListWidget(BuildContext context) {
  ///   return GridView.builder(
  ///     controller: scrollController,  // 必须绑定！
  ///     itemCount: viewModel.items.length,
  ///     itemBuilder: (ctx, i) => buildItem(ctx, viewModel.items[i], i),
  ///   );
  /// }
  /// ```
  Widget? buildListWidget(BuildContext context) => null;

  /// 构建列表 Header（可选）
  Widget? buildHeader(BuildContext context) => null;

  /// 自定义"加载更多"视图（可选）
  ///
  /// @param hasMore 是否还有更多数据
  /// @param isLoadingMore 是否正在加载
  ///
  /// 返回 null 使用默认样式
  Widget? loadMoreFooterBuilder(
    BuildContext context,
    bool hasMore,
    bool isLoadingMore,
  ) =>
      null;

  /// 刷新容器包裹（用于接入第三方刷新库）
  /// 默认使用 RefreshIndicator，可重写此方法接入第三方库（如 pull_to_refresh）
  Widget refreshWrapperBuilder(BuildContext context, Widget child) {
    if (!enableRefresh) return child;
    return RefreshIndicator(
      onRefresh: onRefreshCallback,
      child: child,
    );
  }

  /// 列表体外层包裹
  /// 用于添加 Scrollbar、NotificationListener、吸顶 Header 等额外结构
  Widget listWrapperBuilder(BuildContext context, Widget list) => list;

  /// 提供自定义 ScrollController
  /// 返回 null 使用内部控制器；非空时由外部管理其生命周期
  ScrollController? provideScrollController(BuildContext context) => null;

  /// 下拉刷新回调（供第三方库使用）
  Future<void> onRefreshCallback() async {
    await viewModel.refreshData();
  }

  /// 上拉加载回调（供第三方库使用）
  Future<void> onLoadMoreCallback() async {
    await viewModel.loadMore();
  }

  /// 滚动事件回调
  /// 可用于自定义触底策略或滚动埋点
  void onScroll(BuildContext context, ScrollPosition position) {}

  /// 是否启用自动触底加载
  bool get enableAutoLoadMore => true;

  /// 触底阈值
  double get loadMoreThreshold => 100;

  /// 是否启用下拉刷新
  bool get enableRefresh => false;

  /// 列表页 默认关闭 safeAreaBottom
  @override
  bool get safeAreaBottom => false;

  // ==================== 内部实现 ====================

  /// 页面是否为空：依据列表数据判断
  @override
  bool get isEmptyContent => viewModel.items.isEmpty;

  /// 内部 ScrollController（供子类使用）
  /// 当重写 buildListWidget 时，请绑定此 controller 以支持上拉加载
  @protected
  ScrollController get scrollController => _controller;

  @override
  void initState() {
    super.initState();
    _controller = provideScrollController(context) ?? ScrollController();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (provideScrollController(context) == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// 触底检测：接近底部时尝试加载更多
  void _onScroll() {
    onScroll(context, _controller.position);
    if (!enableAutoLoadMore) return;
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    final offset = _controller.offset;
    if (offset >= max - loadMoreThreshold) {
      onLoadMoreCallback();
    }
  }

  /// 构建成功态内容：列表 + 刷新包裹
  @override
  Widget buildContent(BuildContext context) {
    Widget body = _buildListWidget();
    body = refreshWrapperBuilder(context, body);
    return body;
  }

  /// 构建列表视图：支持自定义或默认实现
  Widget _buildListWidget() {
    final vm = viewModel;
    final theme = Theme.of(context).extension<StatusViewsTheme>();
    final list = buildListWidget(context) ??
        ListView.builder(
          controller: _controller,
          itemCount: vm.items.length + 1,
          itemBuilder: (ctx, i) {
            // 支持自定义 Header
            if (i == 0) {
              final header = buildHeader(ctx);
              if (header != null) return header;
            }

            final last = i == vm.items.length;
            if (last) {
              // 加载失败：显示重试按钮
              if (vm.loadMoreFailed) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vm.loadMoreError?.toString() ?? '加载更多失败',
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: vm.loadMore,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }

              // 用户自定义加载视图
              final customFooter = loadMoreFooterBuilder(
                ctx,
                vm.hasMore,
                vm.isLoadingMore,
              );
              if (customFooter != null) return customFooter;

              // 主题自定义加载视图
              final globalFooter =
                  theme?.loadMoreBuilder?.call(ctx, vm.hasMore);
              if (globalFooter != null) return globalFooter;

              // 默认加载视图
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: vm.hasMore
                      ? const CircularProgressIndicator()
                      : const Text('没有更多了'),
                ),
              );
            }
            final item = vm.items[i];
            return buildItem(ctx, item, i);
          },
        );
    return listWrapperBuilder(context, list);
  }
}
