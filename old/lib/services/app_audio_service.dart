import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import '../models/music_entity.dart';
import '../viewmodels/player_viewmodel.dart';

class AppAudioService {
  static AppAudioHandler? _handler;
  static const String _channelId = 'com.lanke.music.playback_v2';
  static const String _channelName = '媒体播放';
  static const String _channelDescription = '媒体播放控制';

  static AppAudioHandler get handler {
    final handler = _handler;
    if (handler == null) {
      throw StateError('AppAudioService not initialized');
    }
    return handler;
  }

  static Future<void> init() async {
    if (_handler != null) return;
    if (kDebugMode) {
      debugPrint('AudioService.init start');
    }
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      _handler = AppAudioHandler();
      if (kDebugMode) {
        debugPrint('AudioService.init skipped for platform');
      }
      return;
    }
    try {
      _handler = await AudioService.init(
        builder: () => AppAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: _channelId,
          androidNotificationChannelName: _channelName,
          androidNotificationChannelDescription: _channelDescription,
          androidNotificationIcon: 'drawable/ic_notification',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      if (kDebugMode) {
        debugPrint('AudioService.init success');
      }
    } catch (e, stackTrace) {
      _handler = AppAudioHandler();
      if (kDebugMode) {
        debugPrint('AudioService.init failed: $e');
        debugPrint('$stackTrace');
      }
    }
  }

  static void bindPlayer(PlayerViewModel vm) {
    handler.bindPlayer(vm);
  }

  static void updateQueue(List<MusicEntity> queue) {
    handler.updateQueueItems(queue);
  }

  static void updateCurrent(MusicEntity? song) {
    handler.updateCurrentItem(song);
  }

  static void updatePlayback({
    required bool playing,
    required Duration position,
    required Duration duration,
    AudioProcessingState processingState = AudioProcessingState.ready,
  }) {
    handler.updatePlaybackState(
      playing: playing,
      position: position,
      duration: duration,
      processingState: processingState,
    );
  }
}

class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlayerViewModel? _player;

  void bindPlayer(PlayerViewModel vm) {
    _player = vm;
  }

  void updateQueueItems(List<MusicEntity> songs) {
    queue.add(songs.map(_toMediaItem).toList());
  }

  void updateCurrentItem(MusicEntity? song) {
    mediaItem.add(song == null ? null : _toMediaItem(song));
    if (kDebugMode) {
      debugPrint('AudioService.mediaItem ${song?.title ?? 'null'}');
    }
  }

  void updatePlaybackState({
    required bool playing,
    required Duration position,
    required Duration duration,
    AudioProcessingState processingState = AudioProcessingState.ready,
  }) {
    final controls = [
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.stop,
    ];
    final state = playbackState.value;
    playbackState.add(
      state.copyWith(
        controls: controls,
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        playing: playing,
        updatePosition: position,
        bufferedPosition: position,
        processingState: processingState,
        queueIndex: _player?.currentIndex,
        speed: 1.0,
      ),
    );
    if (kDebugMode) {
      debugPrint(
        'AudioService.playback playing=$playing state=$processingState '
        'pos=${position.inMilliseconds} dur=${duration.inMilliseconds}',
      );
    }
    if (mediaItem.value != null && mediaItem.value!.duration != duration) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _player?.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player?.previous();
  }

  MediaItem _toMediaItem(MusicEntity song) {
    final extras = <String, dynamic>{
      'id': song.id,
      'uri': song.uri,
      'isLocal': song.isLocal,
      'sourceId': song.sourceId,
    };
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs == null
          ? null
          : Duration(milliseconds: song.durationMs!),
      extras: extras,
      artUri: song.localCoverPath != null
          ? Uri.file(song.localCoverPath!)
          : null,
    );
  }
}
