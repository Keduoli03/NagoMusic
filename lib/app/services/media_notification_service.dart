import 'package:audio_service/audio_service.dart';

import '../state/song_state.dart';
import 'player_service.dart';

class MediaNotificationService {
  static AudioHandler? _audioHandler;

  static Future<void> init() async {
    if (_audioHandler != null) return;
    _audioHandler = await AudioService.init(
      builder: () => _NagoAudioHandler(PlayerService.instance),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nagomusic.playback',
        androidNotificationChannelName: '音乐播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidShowNotificationBadge: false,
      ),
    );
  }
}

class _NagoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final PlayerService player;

  _NagoAudioHandler(this.player) {
    player.snapshot.addListener(_syncFromPlayer);
    _syncFromPlayer();
  }

  MediaItem _itemFromSong(SongEntity song) {
    final art = (song.localCoverPath ?? '').trim();
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.durationMs != null
          ? Duration(milliseconds: song.durationMs!)
          : null,
      artUri: art.isNotEmpty ? Uri.file(art) : null,
    );
  }

  PlaybackState _stateFromSnap(PlaybackSnapshot snap) {
    final playing = snap.isPlaying;
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ];
    final processing =
        snap.queue.isEmpty ? AudioProcessingState.idle : AudioProcessingState.ready;
    return PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: processing,
      playing: playing,
      updatePosition: snap.position,
      bufferedPosition: snap.bufferedPosition,
      speed: 1.0,
      queueIndex: snap.index >= 0 ? snap.index : null,
    );
  }

  void _syncFromPlayer() {
    final snap = player.snapshot.value;
    final items = snap.queue.map(_itemFromSong).toList();
    queue.add(items);
    final current = snap.song;
    mediaItem.add(current != null ? _itemFromSong(current) : null);
    playbackState.add(_stateFromSnap(snap));
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() => player.stopAndClear();

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) => player.skipToIndex(index);
}
