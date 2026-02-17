import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import '../services/lyrics/lyrics_service.dart';
import '../services/playlists_service.dart';
import '../state/song_state.dart';
import '../state/settings_state.dart';
import 'player_service.dart';

class MediaNotificationService {
  static AudioHandler? _audioHandler;

  static Future<void> init() async {
    if (_audioHandler != null) return;
    await MediaNotificationSettings.ensureLoaded();
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
  static const String _actionCloseApp = 'close_app';
  static const String _actionFavorite = 'favorite';
  String? _currentLyricLine;
  bool _isFavorite = false;

  _NagoAudioHandler(this.player) {
    player.snapshot.addListener(_syncFromPlayer);
    LyricsService.instance.currentLineText.addListener(_onLyricLineChanged);
    MediaNotificationSettings.showLyrics.addListener(
      _onNotificationSettingsChanged,
    );
    MediaNotificationSettings.lyricOnTop.addListener(
      _onNotificationSettingsChanged,
    );
    MediaNotificationSettings.showCloseAction.addListener(
      _onNotificationSettingsChanged,
    );
    MediaNotificationSettings.showFavoriteAction.addListener(
      _onNotificationSettingsChanged,
    );
    _currentLyricLine = LyricsService.instance.currentLineText.value;
    _syncFromPlayer();
  }

  MediaItem _itemFromSong(SongEntity song) {
    final art = (song.localCoverPath ?? '').trim();
    final lyricLine =
        MediaNotificationSettings.showLyrics.value ? _currentLyricLine : null;
    final titleText = song.title.trim();
    final artistText = song.artist.trim();
    final songAndArtist =
        artistText.isEmpty ? titleText : '$titleText · $artistText';
    final lyricOnTop = MediaNotificationSettings.lyricOnTop.value;
    if (lyricOnTop && lyricLine != null) {
      return MediaItem(
        id: song.id,
        title: lyricLine,
        artist: songAndArtist,
        album: song.album,
        duration: song.durationMs != null
            ? Duration(milliseconds: song.durationMs!)
            : null,
        artUri: art.isNotEmpty ? Uri.file(art) : null,
        displayTitle: lyricLine,
        displaySubtitle: songAndArtist,
        displayDescription: artistText.isEmpty ? null : artistText,
      );
    }
    final effectiveArtist = lyricLine ?? song.artist;
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: effectiveArtist,
      album: song.album,
      duration: song.durationMs != null
          ? Duration(milliseconds: song.durationMs!)
          : null,
      artUri: art.isNotEmpty ? Uri.file(art) : null,
      displayTitle: song.title,
      displaySubtitle: lyricLine,
      displayDescription: lyricLine != null ? song.artist : null,
    );
  }

  PlaybackState _stateFromSnap(PlaybackSnapshot snap) {
    final playing = snap.isPlaying;
    final showClose = MediaNotificationSettings.showCloseAction.value;
    final showFavorite = MediaNotificationSettings.showFavoriteAction.value;
    final favoriteIcon = _isFavorite
        ? 'drawable/audio_service_favorite_on'
        : 'drawable/audio_service_favorite';
    final controls = <MediaControl>[];
    if (showClose) {
      controls.add(
        MediaControl.custom(
          name: _actionCloseApp,
          androidIcon: 'drawable/audio_service_close',
          label: '关闭',
        ),
      );
    }
    if (showFavorite) {
      controls.add(
        MediaControl.custom(
          name: _actionFavorite,
          androidIcon: favoriteIcon,
          label: _isFavorite ? '已收藏' : '收藏',
        ),
      );
    }
    final prevIndex = controls.length;
    controls.add(MediaControl.skipToPrevious);
    final playIndex = controls.length;
    controls.add(playing ? MediaControl.pause : MediaControl.play);
    final nextIndex = controls.length;
    controls.add(MediaControl.skipToNext);
    final processing =
        snap.queue.isEmpty ? AudioProcessingState.idle : AudioProcessingState.ready;
    return PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: [prevIndex, playIndex, nextIndex],
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
    _syncMediaItem();
    playbackState.add(_stateFromSnap(snap));
    _refreshFavoriteState();
  }

  void _syncMediaItem() {
    final current = player.snapshot.value.song;
    mediaItem.add(current != null ? _itemFromSong(current) : null);
  }

  void _onLyricLineChanged() {
    _currentLyricLine = LyricsService.instance.currentLineText.value;
    _syncMediaItem();
  }

  void _onNotificationSettingsChanged() {
    _syncMediaItem();
    playbackState.add(_stateFromSnap(player.snapshot.value));
  }

  void _refreshFavoriteState() {
    () async {
      final song = player.snapshot.value.song;
      if (song == null) {
        _updateFavorite(false);
        return;
      }
      final isFav = await PlaylistsService.instance.isSongFavorited(song.id);
      _updateFavorite(isFav);
    }();
  }

  void _updateFavorite(bool value) {
    if (_isFavorite == value) return;
    _isFavorite = value;
    playbackState.add(_stateFromSnap(player.snapshot.value));
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

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name != _actionCloseApp) {
      if (name != _actionFavorite) {
        return super.customAction(name, extras);
      }
      final song = player.snapshot.value.song;
      if (song == null) return;
      if (_isFavorite) {
        await PlaylistsService.instance.removeSongs(
          PlaylistsService.favoritePlaylistId,
          [song.id],
        );
        _updateFavorite(false);
      } else {
        await PlaylistsService.instance.addSongs(
          PlaylistsService.favoritePlaylistId,
          [song.id],
        );
        _updateFavorite(true);
      }
      return;
    }
    await player.pause();
    try {
      SystemNavigator.pop();
    } catch (_) {}
  }
}
