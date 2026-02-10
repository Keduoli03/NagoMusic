import 'package:flutter/foundation.dart';

enum ViewState { idle, loading, success, error }

class BaseViewModel extends ChangeNotifier {
  ViewState _state = ViewState.idle;
  String? _errorMessage;
  bool _isRefreshing = false;
  bool _disposed = false;

  // ==================== Getters ====================
  // 当前视图状态
  ViewState get state => _state;
  // 错误信息
  String? get errorMessage => _errorMessage;
  // 是否正在加载
  bool get isLoading => _state == ViewState.loading;
  // 是否加载失败
  bool get isError => _state == ViewState.error;
  // 是否加载成功
  bool get isSuccess => _state == ViewState.success;
  // 是否空闲状态
  bool get isIdle => _state == ViewState.idle;
  // 是否正在刷新
  bool get isRefreshing => _isRefreshing;
  // 是否已释放
  bool get isDisposed => _disposed;

  // ==================== 状态设置 ====================

  /// 设置视图状态
  void setState(ViewState state, {String? error}) {
    if (_disposed) return;
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }

  /// 设置刷新状态
  void setRefreshing(bool refreshing) {
    if (_disposed) return;
    _isRefreshing = refreshing;
    notifyListeners();
  }

  /// 通知数据变化（仅用于局部刷新）
  void notifyDataChange() {
    if (_disposed) return;
    notifyListeners();
  }

  // ==================== 生命周期 ====================
  /// 初始化钩子
  Future<void> onInit() async {
    // 子类可以重写此方法进行初始化
  }

  /// 刷新数据（钩子）
  Future<void> refreshData() async {
    // 子类可以重写此方法实现刷新逻辑
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
