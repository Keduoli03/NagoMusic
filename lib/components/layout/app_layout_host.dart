import 'dart:async';

import 'package:flutter/material.dart';

import '../feedback/app_toast.dart';
import 'base/app_background.dart';

class AppLayoutHost extends StatelessWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const AppLayoutHost({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return _RootBackHandler(
      navigatorKey: navigatorKey,
      child: AppBackground(child: child),
    );
  }
}

/// Routes system back gestures for the nested base [Navigator]:
/// - while there are in-app pages to go back to, it pops the nested navigator
///   (mirrors [NavigatorPopHandler], which keeps HarmonyOS/Android
///   predictive-back reliable by reflecting the subtree's real pop-ability);
/// - when already at the home page, the first back shows a hint and only the
///   second back within 2s actually exits to the desktop.
class _RootBackHandler extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const _RootBackHandler({required this.navigatorKey, required this.child});

  @override
  State<_RootBackHandler> createState() => _RootBackHandlerState();
}

class _RootBackHandlerState extends State<_RootBackHandler> {
  bool _subtreeCanPop = false;
  bool _armedToExit = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _armExitWindow() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        _armedToExit = false;
        return;
      }
      setState(() => _armedToExit = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _subtreeCanPop ? false : _armedToExit;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_subtreeCanPop) {
          widget.navigatorKey.currentState?.maybePop();
          return;
        }
        AppToast.show(context, '再返回一次退回桌面');
        setState(() => _armedToExit = true);
        _armExitWindow();
      },
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          final next = notification.canHandlePop;
          if (next != _subtreeCanPop) {
            setState(() {
              _subtreeCanPop = next;
              if (next) {
                _armedToExit = false;
                _resetTimer?.cancel();
              }
            });
          }
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
