import 'package:flutter/services.dart';

class MeizuLyricsService {
  static const MethodChannel _channel =
      MethodChannel('com.lanke.nagomusic/meizu_lyrics');

  static Future<bool> checkSupport() async {
    try {
      final bool supported = await _channel.invokeMethod('checkSupport');
      return supported;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateLyric(String text) async {
    try {
      await _channel.invokeMethod('updateLyric', {'text': text});
    } catch (_) {}
  }

  static Future<void> stopLyric() async {
    try {
      await _channel.invokeMethod('stopLyric');
    } catch (_) {}
  }
}
