import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Toast 的语义只影响触感，外观统一为深色纯文字胶囊。
enum ToastType { info, success, error }

/// 模板同款的全局轻量提示。
///
/// 保留原有 API，业务调用无需迁移；成功与失败只在这里统一提供触感反馈。
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _notify(type);
    _dismiss();

    final controllerKey = GlobalKey<_ToastWidgetState>();
    _entry = OverlayEntry(
      builder: (_) => _ToastWidget(key: controllerKey, message: message),
    );
    overlay.insert(_entry!);
    _timer = Timer(duration, () async {
      await controllerKey.currentState?.hide();
      _dismiss();
    });
  }

  static void _notify(ToastType type) {
    try {
      switch (type) {
        case ToastType.success:
          HapticFeedback.lightImpact();
          Future<void>.delayed(
            const Duration(milliseconds: 90),
            HapticFeedback.lightImpact,
          );
          return;
        case ToastType.error:
          HapticFeedback.heavyImpact();
          return;
        case ToastType.info:
          return;
      }
    } catch (_) {
      // 无触感硬件或平台不支持时不影响提示本身。
    }
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({super.key, required this.message});

  final String message;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  static const double _bottomGap = 96;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
    reverseDuration: AppMotion.fast,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curve,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.curveIn,
    reverseCurve: Curves.easeIn,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.55),
    end: Offset.zero,
  ).animate(_pop);
  late final Animation<double> _scale = Tween<double>(
    begin: 0.88,
    end: 1,
  ).animate(_pop);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  Future<void> hide() async {
    if (mounted) await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboard = mediaQuery.viewInsets.bottom;
    final bottom = keyboard > 0
        ? keyboard + AppSpacing.lg
        : mediaQuery.padding.bottom + _bottomGap;

    return Positioned(
      left: AppSpacing.xl,
      right: AppSpacing.xl,
      bottom: bottom,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xE6303030),
                      borderRadius: AppRadii.rPill,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyLg.on(Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
