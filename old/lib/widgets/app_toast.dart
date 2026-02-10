import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/router/navigator_util.dart';

enum ToastType { info, success, error }

class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void show(
    BuildContext? context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    _removeCurrent();

    OverlayState? overlay;
    
    // 1. Try to find overlay from context if provided
    if (context != null) {
      try {
        overlay = Overlay.of(context, rootOverlay: true);
      } catch (_) {}
      
      // Retry without rootOverlay if failed
      if (overlay == null) {
         try {
           overlay = Overlay.of(context);
         } catch (_) {}
      }
    }

    // 2. Fallback to global navigator overlay
    overlay ??= NavigatorUtil.navigatorKey.currentState?.overlay;

    if (overlay == null) {
      debugPrint('AppToast: No overlay found for message: $message');
      return;
    }
    
    final entry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDismiss: _removeCurrent,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _timer = Timer(duration + const Duration(milliseconds: 300), () {
      _removeCurrent();
    });
  }

  static void _removeCurrent() {
    _timer?.cancel();
    _timer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );

    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.2), 
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    _hideTimer = Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
    
    App.playerBarBottomPadding.addListener(_onPaddingChanged);
  }

  @override
  void dispose() {
    App.playerBarBottomPadding.removeListener(_onPaddingChanged);
    _controller.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }
  
  void _onPaddingChanged() {
    if (mounted) setState(() {});
  }

  Color _getIconColor(bool isDark) {
    switch (widget.type) {
      case ToastType.success:
        return const Color(0xFF4CAF50); // Green
      case ToastType.error:
        return const Color(0xFFE53935); // Red
      case ToastType.info:
        return const Color(0xFF2196F3); // Blue
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.error:
        return Icons.error;
      case ToastType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Modern style:
    // Dark: Dark grey background, light text.
    // Light: White background, dark text.
    final backgroundColor = isDark ? const Color(0xFF32363C) : Colors.white;
    final textColor = isDark ? Colors.white.withAlpha(230) : Colors.black87;
    final shadowColor = Colors.black.withAlpha(((isDark ? 0.3 : 0.1) * 255).round());
    
    // Calculate safe bottom position based on player bar
    final playerPadding = App.playerBarBottomPadding.value;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    
    // If player bar is visible (padding >= 0) or partially visible, move toast above it.
    // If hidden (-120), use standard margin.
    double bottomOffset = safeBottom + 24; // Default standard margin
    
    if (playerPadding > -50) {
      // Player bar is visible
      // padding + height(72) + extra margin
      bottomOffset = safeBottom + playerPadding + 72 + 16;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      bottom: bottomOffset,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _offset,
            child: FadeTransition(
              opacity: _opacity,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIcon(),
                      size: 20,
                      color: _getIconColor(isDark),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
