import 'package:flutter/widgets.dart';

/// 全局动效刻度。
abstract final class AppMotion {
  /// 150ms —— 点击、勾选等轻量反馈。
  static const fast = Duration(milliseconds: 150);

  /// 220ms —— 控件与 Toast 的常规过渡。
  static const base = Duration(milliseconds: 220);

  /// 320ms —— 页面级转场与面板。
  static const slow = Duration(milliseconds: 320);

  static const curve = Curves.easeOutCubic;
  static const curveIn = Curves.easeOutBack;
}
