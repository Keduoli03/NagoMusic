import 'package:flutter/material.dart';

/// Loading 工具类 - 基于 Overlay 的原生实现
/// 
/// 优点：
/// 1. 零第三方依赖：保持项目纯洁，不增加 pubspec.yaml 负担。
/// 2. 灵活性高：完全基于 Flutter 原生机制，易于自定义 UI 样式。
/// 3. 轻量级：不占用额外打包体积。
class LoadingUtil {
  static OverlayEntry? _overlayEntry;

  /// 显示 Loading
  /// 
  /// [context] 上下文
  /// [message] 加载提示文字
  static void show(BuildContext context, {String? message}) {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 隐藏 Loading
  static void dismiss() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
