import 'package:flutter/material.dart';

import '../theme/status_views_theme.dart';
import 'base_viewmodel.dart';

/// Page 基类
///
/// 提供统一的页面结构和状态处理
///
/// 示例：
/// ```dart
/// class HomePage extends BasePage<HomeViewModel> {
///   const HomePage({super.key});
///
///   @override
///   State<HomePage> createState() => _HomePageState();
/// }
///
/// class _HomePageState extends BasePageState<HomeViewModel, HomePage> {
///   @override
///   HomeViewModel createViewModel() => HomeViewModel();
///
///   @override
///   String get title => '首页';
///
///   @override
///   Widget buildContent(BuildContext context) {
///     return Center(
///       child: Text('Counter: ${viewModel.counter}'),
///     );
///   }
/// }
/// ```
abstract class BasePage<VM extends BaseViewModel> extends StatefulWidget {
  const BasePage({super.key});

  @override
  State<BasePage<VM>> createState();
}

/// Page State 基类
abstract class BasePageState<VM extends BaseViewModel, T extends BasePage<VM>>
    extends State<T> {
  /// ViewModel 实例
  late final VM viewModel;

  // ==================== 子类需要实现的方法 ====================

  /// 创建 ViewModel
  VM createViewModel();

  /// 构建内容区域
  Widget buildContent(BuildContext context);

  // ==================== 可选重写的 UI 配置 ====================

  /// 是否显示 AppBar（默认 true）
  bool get showAppBar => true;

  /// AppBar 标题（默认空串）
  String get title => '';

  /// AppBar 操作按钮（默认 null）
  List<Widget>? get actions => null;

  /// 是否显示返回按钮（默认自动判断）
  bool get showBackButton => true;

  /// 背景颜色（默认 null）
  Color? get backgroundColor => null;

  /// 是否启用 SafeArea（默认 true）
  bool get useSafeArea => true;

  /// SafeArea 上边框（默认 true）
  bool get safeAreaTop => true;

  /// SafeArea 下边框（默认 true）
  bool get safeAreaBottom => true;

  // ==================== 生命周期 ====================

  @override
  void initState() {
    super.initState();
    viewModel = createViewModel();
    _setupListener();
    viewModel.onInit();
  }

  /// 设置监听器
  void _setupListener() {
    // 所有状态管理器都使用统一的 addListener 方式
    viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    viewModel.removeListener(_onViewModelChanged);
    viewModel.dispose();
    super.dispose();
  }

  /// ViewModel 变化回调
  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==================== UI 构建 ====================

  @override
  Widget build(BuildContext context) {
    Widget body = _buildBody();
    body = buildSafeArea(child: body);
    body = buildScaffold(body: body);
    return body;
  }

  /// 构建 SafeArea
  Widget buildSafeArea({required Widget child}) {
    return useSafeArea
        ? SafeArea(
            top: safeAreaTop,
            bottom: safeAreaBottom,
            child: child,
          )
        : child;
  }

  /// 构建 AppBar
  PreferredSizeWidget? buildAppBar() {
    return AppBar(
      title: Text(title),
      actions: actions,
      automaticallyImplyLeading: showBackButton,
    );
  }

  /// 构建 Scaffold
  Widget buildScaffold({required Widget body}) {
    return Scaffold(
      appBar: showAppBar ? buildAppBar() : null,
      backgroundColor: backgroundColor,
      body: body,
    );
  }

  /// 构建 Body
  Widget _buildBody() {
    final theme = Theme.of(context).extension<StatusViewsTheme>();

    if (viewModel.isLoading) {
      final global = theme?.loadingBuilder?.call(context);
      return global ?? buildLoading();
    }

    if (viewModel.isError) {
      final global = theme?.errorBuilder?.call(context, viewModel.errorMessage);
      return global ?? buildError();
    }

    if (isEmptyContent) {
      final global = theme?.emptyBuilder?.call(context);
      return global ?? buildEmpty();
    }

    return buildContent(context);
  }

  // ==================== 可重写的 UI 组件 ====================

  /// 构建 Loading 视图
  Widget buildLoading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  /// 构建错误视图
  Widget buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            viewModel.errorMessage ?? '加载失败',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: viewModel.refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建空视图
  Widget buildEmpty() {
    return const Center(
      child: Text('暂无数据'),
    );
  }

  /// 页面是否为空（默认 false，子类可重写）
  bool get isEmptyContent => false;

  /// 显示 SnackBar
  void showSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  /// 显示 Loading Dialog
  void showLoadingDialog({String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message ?? '加载中...'),
          ],
        ),
      ),
    );
  }

  /// 隐藏 Loading Dialog
  void hideLoadingDialog() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
