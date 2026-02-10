import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';

enum RefreshRateMode {
  auto,
  high,
  low,
}

class DisplayModeService {
  DisplayModeService._();

  static RefreshRateMode get currentMode {
    final modeStr = StorageUtil.getString(StorageKeys.refreshRateMode) ?? 'auto';
    return RefreshRateMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => RefreshRateMode.auto,
    );
  }

  static final modeNotifier = ValueNotifier<RefreshRateMode>(currentMode);

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    modeNotifier.value = currentMode;
    await _applyMode(currentMode);
  }

  static Future<void> setMode(RefreshRateMode mode) async {
    if (!Platform.isAndroid) return;
    await StorageUtil.setString(StorageKeys.refreshRateMode, mode.name);
    modeNotifier.value = mode;
    await _applyMode(mode);
  }

  static Future<void> _applyMode(RefreshRateMode mode) async {
    try {
      switch (mode) {
        case RefreshRateMode.auto:
          await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
          break;
        case RefreshRateMode.high:
          await FlutterDisplayMode.setHighRefreshRate();
          break;
        case RefreshRateMode.low:
          await FlutterDisplayMode.setLowRefreshRate();
          break;
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to set display mode: $e');
    } catch (e) {
      debugPrint('Error setting display mode: $e');
    }
  }

  static Future<List<DisplayMode>> getSupportedModes() async {
    if (!Platform.isAndroid) return [];
    try {
      return await FlutterDisplayMode.supported;
    } catch (e) {
      return [];
    }
  }
}
