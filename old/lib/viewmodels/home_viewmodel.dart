import '../core/index.dart';

class HomeViewModel extends BaseViewModel {
  int _counter = 0;

  int get counter => _counter;

  /// 初始化（函数级注释）
  ///
  /// - 首屏保持成功态，展示既有 UI
  @override
  Future<void> onInit() async {
    super.onInit();
    setState(ViewState.success);
  }

  void increment() {
    _counter++;
    notifyDataChange();
  }

  void decrement() {
    if (_counter > 0) {
      _counter--;
      notifyDataChange();
    }
  }

  void reset() {
    _counter = 0;
    notifyDataChange();
  }
}
