import 'package:flutter/services.dart';

class MeizuLyricsService {
  static const MethodChannel _channel = MethodChannel('com.example.vibe_music/meizu_lyrics');

  /// 检查设备是否支持魅族状态栏歌词
  static Future<bool> checkSupport() async {
    try {
      final bool supported = await _channel.invokeMethod('checkSupport');
      return supported;
    } catch (e) {
      return false;
    }
  }

  /// 更新歌词
  static Future<void> updateLyric(String text) async {
    try {
      await _channel.invokeMethod('updateLyric', {'text': text});
    } catch (e) {
      // ignore
    }
  }

  /// 停止显示歌词
  static Future<void> stopLyric() async {
    try {
      await _channel.invokeMethod('stopLyric');
    } catch (e) {
      // ignore
    }
  }
}
