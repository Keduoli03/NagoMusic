import 'package:flutter/material.dart';

class AppFonts {
  // 顶部栏标题字号
  static const double topBarTitleSize = 20;

  static TextStyle topBarTitleStyle(TextTheme textTheme) {
    final base = textTheme.titleLarge ?? const TextStyle();
    return base.copyWith(fontSize: topBarTitleSize);
  }
}
