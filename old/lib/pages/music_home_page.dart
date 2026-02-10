import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../viewmodels/player_viewmodel.dart';
import 'home_page.dart';

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});
  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  @override
  void initState() {
    super.initState();
    final vm = PlayerViewModel();
    vm.hydrateForUi();
    Future.microtask(() async {
      await _checkPermissions();
      if (!mounted) return;
      await vm.init();
    });
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (kDebugMode) {
      debugPrint('Notification permission status: $status');
    }
    if (status.isGranted) {
      return;
    }
    final result = await Permission.notification.request();
    if (kDebugMode) {
      debugPrint('Notification permission request result: $result');
    }
    if (result.isGranted) {
      return;
    }
    if (!mounted) return;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要通知权限'),
        content: const Text('请在系统设置中开启通知权限，否则通知栏不会显示播放控制。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (shouldOpen == true) {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomePage();
  }
}


