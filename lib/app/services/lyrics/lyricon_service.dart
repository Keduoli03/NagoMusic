import 'package:flutter/services.dart';
import 'package:flutter_lyric/core/lyric_model.dart';

import '../../state/song_state.dart';

class LyriconService {
  static const MethodChannel _channel =
      MethodChannel('com.lanke.nagomusic/lyricon');

  static Future<void> setPlaybackState(bool isPlaying) async {
    try {
      await _channel.invokeMethod('setPlaybackState', {'isPlaying': isPlaying});
    } catch (_) {}
  }

  static Future<void> setSong(
    SongEntity song,
    LyricModel? lyricModel, {
    required bool hideTranslation,
  }) async {
    try {
      final List<Map<String, dynamic>> lyricsList = [];
      if (lyricModel != null) {
        for (final line in lyricModel.lines) {
          lyricsList.add({
            'text': line.text,
            'translation': hideTranslation ? null : line.translation,
            'begin': line.start.inMilliseconds,
            'end': line.end?.inMilliseconds ?? (line.start.inMilliseconds + 3000),
            'words': line.words
                ?.map(
                  (w) => {
                    'text': w.text,
                    'begin': w.start.inMilliseconds,
                    'end': w.end?.inMilliseconds ?? w.start.inMilliseconds,
                  },
                )
                .toList(),
          });
        }
      }

      await _channel.invokeMethod('setSong', {
        'id': song.id,
        'name': song.title,
        'artist': song.artist,
        'duration': song.durationMs ?? 0,
        'lyrics': lyricsList,
      });
    } catch (_) {}
  }

  static Future<void> updatePosition(int positionMs) async {
    try {
      await _channel.invokeMethod('updatePosition', {'position': positionMs});
    } catch (_) {}
  }

  static Future<void> setDisplayTranslation(bool display) async {
    try {
      await _channel.invokeMethod('setDisplayTranslation', {'display': display});
    } catch (_) {}
  }

  static Future<void> setServiceEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setServiceEnabled', {'enabled': enabled});
    } catch (_) {}
  }
}
