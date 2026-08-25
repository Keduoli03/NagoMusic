import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/log/log.dart';
import '../services/lyrics/lyrics_service.dart';
import '../services/playlists_service.dart';
import '../state/song_state.dart';
import '../state/settings_state.dart';
import 'android_platform_service.dart';
import 'player_service.dart';

const String _logTag = 'MediaNotification';

class MediaNotificationService {
  static AudioHandler? _audioHandler;
  static VoidCallback? _initListener;
  static bool _initStarted = false;

  static Future<void> init({bool force = false}) async {
    if (_audioHandler != null || _initStarted) return;
    await MediaNotificationSettings.ensureLoaded();
    final player = PlayerService.instance;
    final snap = player.snapshot.value;
    if (!force && snap.song == null && !snap.isPlaying) {
      if (_initListener == null) {
        _initListener = () {
          final current = player.snapshot.value;
          if (current.song == null && !current.isPlaying) return;
          if (_initListener != null) {
            player.snapshot.removeListener(_initListener!);
            _initListener = null;
          }
          init(force: true);
        };
        player.snapshot.addListener(_initListener!);
      }
      return;
    }
    _initStarted = true;
    _debugLog('init start force=$force');
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        _debugLog('requesting Android notification permission');
        await Permission.notification.request();
      }
    }
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
    _debugLog('init completed');
    _initStarted = false;
  }

  static void _debugLog(String message) => AppLog.instance.d(_logTag, message);
}

class _NagoAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final PlayerService player;
  static const String _actionCloseApp = 'close_app';
  static const String _actionFavorite = 'favorite';
  String? _currentLyricLine;
  String? _lastSongId;
  bool _isFavorite = false;
  String? _lastQueueKey;
  String? _lastMediaItemKey;
  String? _lastPlaybackStateKey;
  bool _supportsCustomActions = true;

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
    _loadPlatformCapabilities();
    _syncFromPlayer();
  }

  Future<void> _loadPlatformCapabilities() async {
    _supportsCustomActions = await AndroidPlatformService.instance
        .supportsNotificationCustomActions();
    _debugLog('supports custom actions=$_supportsCustomActions');
    _lastPlaybackStateKey = null;
    _syncPlaybackState(player.snapshot.value);
  }

  void _debugLog(String message) => AppLog.instance.d(_logTag, message);

  MediaItem _itemFromSong(SongEntity song) {
    final art = (song.localCoverPath ?? '').trim();
    final lyricLine = MediaNotificationSettings.showLyrics.value
        ? _currentLyricLine
        : null;
    final titleText = song.title.trim();
    final artistText = song.artist.trim();
    final songAndArtist = artistText.isEmpty
        ? titleText
        : '$titleText · $artistText';
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
    final showClose =
        _supportsCustomActions &&
        MediaNotificationSettings.showCloseAction.value;
    final showFavorite =
        _supportsCustomActions &&
        MediaNotificationSettings.showFavoriteAction.value;
    final favoriteIcon = _isFavorite
        ? 'drawable/audio_service_favorite_on'
        : 'drawable/audio_service_favorite';
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ];
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
    final processing = snap.queue.isEmpty
        ? AudioProcessingState.idle
        : AudioProcessingState.ready;
    return PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
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
    final songId = snap.song?.id;
    final songChanged = songId != _lastSongId;
    if (songId != _lastSongId) {
      _lastSongId = songId;
      _currentLyricLine = null;
      _debugLog('song changed to ${snap.song?.title ?? 'none'}');
    }
    _syncQueue(snap);
    _syncMediaItem();
    _syncPlaybackState(snap);
    if (songChanged) {
      _refreshFavoriteState();
    }
  }

  void _syncQueue(PlaybackSnapshot snap) {
    final queueKey = snap.queue.map((song) => song.id).join('|');
    if (queueKey == _lastQueueKey) return;
    _lastQueueKey = queueKey;
    queue.add(snap.queue.map(_itemFromSong).toList());
  }

  void _syncMediaItem() {
    final current = player.snapshot.value.song;
    final item = current != null ? _itemFromSong(current) : null;
    final itemKey = item == null
        ? 'none'
        : [
            item.id,
            item.title,
            item.artist ?? '',
            item.displayTitle ?? '',
            item.displaySubtitle ?? '',
            item.artUri?.toString() ?? '',
          ].join('|');
    if (itemKey == _lastMediaItemKey) return;
    _lastMediaItemKey = itemKey;
    mediaItem.add(item);
  }

  void _syncPlaybackState(PlaybackSnapshot snap) {
    final next = _stateFromSnap(snap);
    final stateKey = [
      snap.song?.id ?? '',
      snap.index,
      snap.isPlaying,
      next.processingState.name,
      snap.position.inMilliseconds,
      snap.bufferedPosition.inMilliseconds,
      snap.duration?.inMilliseconds ?? -1,
      _isFavorite,
      MediaNotificationSettings.showLyrics.value,
      MediaNotificationSettings.lyricOnTop.value,
      MediaNotificationSettings.showCloseAction.value,
      MediaNotificationSettings.showFavoriteAction.value,
      _supportsCustomActions,
    ].join('|');
    if (stateKey == _lastPlaybackStateKey) return;
    _lastPlaybackStateKey = stateKey;
    playbackState.add(next);
  }

  void _onLyricLineChanged() {
    _currentLyricLine = LyricsService.instance.currentLineText.value;
    _syncMediaItem();
  }

  void _onNotificationSettingsChanged() {
    if (!MediaNotificationSettings.showLyrics.value) {
      _currentLyricLine = null;
    } else {
      _currentLyricLine = LyricsService.instance.currentLineText.value;
    }
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
    _debugLog('favorite state changed: $_isFavorite');
    playbackState.add(_stateFromSnap(player.snapshot.value));
  }

  @override
  Future<void> skipToNext() {
    _debugLog('skipToNext action');
    return player.next();
  }

  @override
  Future<void> skipToPrevious() {
    _debugLog('skipToPrevious action');
    return player.previous();
  }

  @override
  Future<void> seek(Duration position) {
    _debugLog('seek action ${position.inMilliseconds}ms');
    return player.seek(position);
  }

  @override
  Future<void> skipToQueueItem(int index) {
    _debugLog('skipToQueueItem action index=$index');
    return player.skipToIndex(index);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    _debugLog('customAction name=$name');
    if (name != _actionCloseApp) {
      if (name != _actionFavorite) {
        return super.customAction(name, extras);
      }
      final song = player.snapshot.value.song;
      if (song == null) return;
      if (_isFavorite) {
        _debugLog('favorite remove action song=${song.title}');
        await PlaylistsService.instance.removeSongs(
          PlaylistsService.favoritePlaylistId,
          [song.id],
        );
        _updateFavorite(false);
      } else {
        _debugLog('favorite add action song=${song.title}');
        await PlaylistsService.instance.addSongs(
          PlaylistsService.favoritePlaylistId,
          [song.id],
        );
        _updateFavorite(true);
      }
      return;
    }
    _debugLog('close action');
    await stop();
  }

  @override
  Future<void> play() {
    _debugLog('play action');
    return player.play();
  }

  @override
  Future<void> pause() {
    _debugLog('pause action');
    return player.pause();
  }

  @override
  Future<void> stop() {
    _debugLog('stop action');
    return player.stopAndClear();
  }
}
