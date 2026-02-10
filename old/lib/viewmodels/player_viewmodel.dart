import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as flmodel;
import 'package:just_audio/just_audio.dart';
import 'package:signals/signals.dart';
import '../core/cache/cache_manager.dart';
import '../core/database/database_helper.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../models/music_entity.dart';
import '../services/app_audio_service.dart';
import '../services/audio_proxy_server.dart';
import '../services/lyrics/lyricon_service.dart';
import '../services/lyrics/meizu_lyrics_service.dart';
import '../services/tag_probe_service.dart';
import '../utils/lyrics_parser.dart';
import 'library_viewmodel.dart';

enum _MetaFetchState { idle, fetching, success, failed }

class PlayerViewModel with WidgetsBindingObserver {
  static final PlayerViewModel _instance = PlayerViewModel._internal();
  factory PlayerViewModel() => _instance;
  PlayerViewModel._internal() {
    WidgetsBinding.instance.addObserver(this);
    
    // Lyrics Persistence Effects
    effect(() => StorageUtil.setDouble(StorageKeys.lyricsFontSize, _lyricsFontSizeSignal.value));
    effect(() => StorageUtil.setDouble(StorageKeys.lyricsLineGap, _lyricsLineGapSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.showLyricsTranslation, _showLyricsTranslationSignal.value));
    effect(() => StorageUtil.setString(StorageKeys.lyricsAlignment, _lyricsAlignmentSignal.value));
    effect(() => StorageUtil.setString(StorageKeys.miniLyricsAlignment, _miniLyricsAlignmentSignal.value));
    effect(() => StorageUtil.setDouble(StorageKeys.lyricsActiveFontSize, _lyricsActiveFontSizeSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.lyricsDragToSeek, _lyricsDragToSeekSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.lyricsKaraokeEnabled, _lyricsKaraokeEnabledSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.lyriconEnabled, _lyriconEnabledSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.lyriconForceKaraoke, _lyriconForceKaraokeSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.lyriconHideTranslation, _lyriconHideTranslationSignal.value));
    effect(() => StorageUtil.setBool(StorageKeys.meizuLyricsEnabled, _meizuLyricsEnabledSignal.value));
  }

  bool _initialized = false;

  late AudioPlayer _player;
  final Random _random = Random();
  final AudioProxyServer _localServer = AudioProxyServer();
  String? _title;
  String? _artist;
  Uint8List? _artwork;
  ui.Color _dominantColor = const ui.Color(0xFF1A1A1A);
  String? _lyrics;
  String? _lyricsTranslation;
  String? _rawLyrics;
  List<LyricLine> _lyricsLines = [];
  flmodel.LyricModel? _lyricModel;
  int _currentLyricIndex = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isFetchingTags = false;
  PlaybackMode _mode = _loadPlaybackMode();
  Timer? _sleepTimer;
  DateTime? _sleepUntil;
  bool _sleepUntilSongEnd = false;
  ThemeMode _playbackThemeMode = _loadPlaybackThemeMode();
  bool _dynamicGradientEnabled = _loadDynamicGradientEnabled();
  double _dynamicGradientSaturation = _loadDynamicGradientSaturation();
  double _dynamicGradientHueShift = _loadDynamicGradientHueShift();

  // Lyrics Settings Signals
  final Signal<double> _lyricsFontSizeSignal = signal(
      StorageUtil.getDoubleOrDefault(StorageKeys.lyricsFontSize, defaultValue: 20.0)
          .clamp(14.0, 32.0)
          .toDouble(),);
  final Signal<double> _lyricsLineGapSignal = signal(
      StorageUtil.getDoubleOrDefault(StorageKeys.lyricsLineGap, defaultValue: 14.0,),);
  final Signal<bool> _showLyricsTranslationSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.showLyricsTranslation, defaultValue: true,),);
  final Signal<String> _lyricsAlignmentSignal = signal(
      StorageUtil.getStringOrDefault(StorageKeys.lyricsAlignment, defaultValue: 'center',),);
  final Signal<String> _miniLyricsAlignmentSignal = signal(
      StorageUtil.getStringOrDefault(StorageKeys.miniLyricsAlignment, defaultValue: 'center',),);
  final Signal<double> _lyricsActiveFontSizeSignal = signal(
      StorageUtil.getDoubleOrDefault(StorageKeys.lyricsActiveFontSize, defaultValue: 26.0)
          .clamp(16.0, 48.0)
          .toDouble(),);
  final Signal<bool> _lyricsDragToSeekSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.lyricsDragToSeek, defaultValue: true,),);
  final Signal<bool> _lyricsKaraokeEnabledSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.lyricsKaraokeEnabled, defaultValue: false,),);
  final Signal<bool> _lyriconEnabledSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.lyriconEnabled, defaultValue: false,),);
  final Signal<bool> _lyriconForceKaraokeSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.lyriconForceKaraoke, defaultValue: false,),);
  final Signal<bool> _lyriconHideTranslationSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.lyriconHideTranslation, defaultValue: false,),);
  final Signal<bool> _meizuLyricsEnabledSignal = signal(
      StorageUtil.getBoolOrDefault(StorageKeys.meizuLyricsEnabled, defaultValue: false,),);
  final Map<String, String> _webDavLyricsCache = {};
  final Map<String, Uint8List> _webDavCoverCache = {};
  final Set<String> _webDavMetadataLoading = {};
  final Map<String, DateTime> _webDavMetadataLastFetch = {};
  final Map<String, DateTime> _webDavMetadataBlockedUntil = {};
  final Map<String, _MetaFetchState> _webDavLyricsState = {};
  final Map<String, _MetaFetchState> _webDavCoverState = {};
  
  List<MusicEntity> _queue = [];
  int _currentIndex = -1;
  String? _lastReportedMediaId;
  int _playRequestId = 0;
  DateTime _lastPersistedStateTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sessionHydrated = false;
  bool _hasRestoredPosition = false;

  final Signal<int> playbackTick = signal(0);
  final Signal<int> queueTick = signal(0);
  final Signal<int> lyricsTick = signal(0);
  final Signal<int> uiTick = signal(0);
  final Signal<int> sleepTick = signal(0);
  final Signal<int> tagTick = signal(0);

  void _bump(Signal<int> tick) {
    tick.value++;
  }

  String? get title => _title;
  String? get artist => _artist;
  Uint8List? get artwork => _artwork;
  ui.Color get dominantColor => _dominantColor;
  String? get lyrics => _lyrics;
  String? get lyricsTranslation => _lyricsTranslation;
  List<LyricLine> get lyricsLines => _lyricsLines;
  flmodel.LyricModel? get lyricModel => _lyricModel;
  double get lyricsFontSize => _lyricsFontSizeSignal.value;
  double get lyricsLineGap => _lyricsLineGapSignal.value;
  bool get showLyricsTranslation => _showLyricsTranslationSignal.value;
  String get lyricsAlignment => _lyricsAlignmentSignal.value;
  String get miniLyricsAlignment => _miniLyricsAlignmentSignal.value;
  double get lyricsActiveFontSize => _lyricsActiveFontSizeSignal.value;
  bool get lyricsDragToSeek => _lyricsDragToSeekSignal.value;
  bool get lyricsKaraokeEnabled => _lyricsKaraokeEnabledSignal.value;
  bool get lyriconEnabled => _lyriconEnabledSignal.value;
  bool get lyriconForceKaraoke => _lyriconForceKaraokeSignal.value;
  bool get lyriconHideTranslation => _lyriconHideTranslationSignal.value;
  bool get meizuLyricsEnabled => _meizuLyricsEnabledSignal.value;
  int get currentLyricIndex => _currentLyricIndex;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isFetchingTags => _isFetchingTags;
  PlaybackMode get mode => _mode;
  bool get singleLoop => _mode == PlaybackMode.single;
  bool get isSleepTimerActive => _sleepTimer != null;
  Duration? get sleepRemaining => _sleepUntil?.difference(DateTime.now());
  bool get sleepUntilSongEnd => _sleepUntilSongEnd;
  String? get sleepTimerDisplayText {
    final remaining = sleepRemaining;
    if (remaining == null || remaining <= Duration.zero) return null;
    final totalMinutes = remaining.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }
  ThemeMode get playbackThemeMode => _playbackThemeMode;
  bool get dynamicGradientEnabled => _dynamicGradientEnabled;
  double get dynamicGradientSaturation => _dynamicGradientSaturation;
  double get dynamicGradientHueShift => _dynamicGradientHueShift;
  List<MusicEntity> get queue => _queue;
  int get currentIndex => _currentIndex;
  MusicEntity? get currentSong => (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;

  static ThemeMode _loadPlaybackThemeMode() {
    final raw = StorageUtil.getStringOrDefault(
      StorageKeys.playbackThemeMode,
      defaultValue: 'system',
    );
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static PlaybackMode _loadPlaybackMode() {
    final raw = StorageUtil.getStringOrDefault(
      StorageKeys.playbackMode,
      defaultValue: 'loop',
    );
    return PlaybackMode.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => PlaybackMode.loop,
    );
  }

  static bool _loadDynamicGradientEnabled() {
    return StorageUtil.getBoolOrDefault(
      StorageKeys.dynamicGradientEnabled,
      defaultValue: false,
    );
  }

  static double _loadDynamicGradientSaturation() {
    return StorageUtil.getDoubleOrDefault(
      StorageKeys.dynamicGradientSaturation,
      defaultValue: 1.0,
    );
  }

  static double _loadDynamicGradientHueShift() {
    return StorageUtil.getDoubleOrDefault(
      StorageKeys.dynamicGradientHueShift,
      defaultValue: 30.0,
    );
  }

  Future<void> setDynamicGradientEnabled(bool enabled) async {
    _dynamicGradientEnabled = enabled;
    _bump(uiTick);
    await StorageUtil.setBool(StorageKeys.dynamicGradientEnabled, enabled);
  }

  Future<void> setDynamicGradientSaturation(double value) async {
    _dynamicGradientSaturation = value;
    _bump(uiTick);
    await StorageUtil.setDouble(StorageKeys.dynamicGradientSaturation, value);
  }

  Future<void> setDynamicGradientHueShift(double value) async {
    _dynamicGradientHueShift = value;
    _bump(uiTick);
    await StorageUtil.setDouble(StorageKeys.dynamicGradientHueShift, value);
  }

  void setLyricsFontSize(double size) {
    final clamped = size.clamp(14.0, 32.0).toDouble();
    if (_lyricsFontSizeSignal.value != clamped) {
      _lyricsFontSizeSignal.value = clamped;
      _bump(lyricsTick);
    }
  }

  void setLyricsLineGap(double gap) {
    if (_lyricsLineGapSignal.value != gap) {
      _lyricsLineGapSignal.value = gap;
      _bump(lyricsTick);
    }
  }

  void setShowLyricsTranslation(bool show) {
    if (_showLyricsTranslationSignal.value != show) {
      _showLyricsTranslationSignal.value = show;
      _bump(lyricsTick);
    }
  }

  void setLyricsAlignment(String alignment) {
    if (_lyricsAlignmentSignal.value != alignment) {
      _lyricsAlignmentSignal.value = alignment;
      _bump(lyricsTick);
    }
  }

  void setMiniLyricsAlignment(String alignment) {
    if (_miniLyricsAlignmentSignal.value != alignment) {
      _miniLyricsAlignmentSignal.value = alignment;
      _bump(lyricsTick);
    }
  }

  void setLyricsActiveFontSize(double size) {
    final clamped = size.clamp(16.0, 48.0).toDouble();
    if (_lyricsActiveFontSizeSignal.value != clamped) {
      _lyricsActiveFontSizeSignal.value = clamped;
      _bump(lyricsTick);
    }
  }

  void setLyricsDragToSeek(bool enabled) {
    if (_lyricsDragToSeekSignal.value != enabled) {
      _lyricsDragToSeekSignal.value = enabled;
      _bump(lyricsTick);
    }
  }

  void setLyricsKaraokeEnabled(bool enabled) {
    if (_lyricsKaraokeEnabledSignal.value != enabled) {
      _lyricsKaraokeEnabledSignal.value = enabled;
      _rebuildLyricsOutputs();
      _bump(lyricsTick);
    }
  }

  void setLyriconEnabled(bool enabled) {
    if (_lyriconEnabledSignal.value != enabled) {
      _lyriconEnabledSignal.value = enabled;
      _bump(lyricsTick);
      _updateLyriconState();
    }
  }

  void setLyriconForceKaraoke(bool enabled) {
    if (_lyriconForceKaraokeSignal.value != enabled) {
      _lyriconForceKaraokeSignal.value = enabled;
      _bump(lyricsTick);
      _updateLyriconState();
    }
  }

  void setLyriconHideTranslation(bool enabled) {
    if (_lyriconHideTranslationSignal.value != enabled) {
      _lyriconHideTranslationSignal.value = enabled;
      _bump(lyricsTick);
      _updateLyriconState();
    }
  }

  void setMeizuLyricsEnabled(bool enabled) {
    if (_meizuLyricsEnabledSignal.value != enabled) {
      _meizuLyricsEnabledSignal.value = enabled;
      _bump(lyricsTick);
      if (enabled) {
        if (_currentLyricIndex >= 0 && _currentLyricIndex < _lyricsLines.length) {
          MeizuLyricsService.updateLyric(_lyricsLines[_currentLyricIndex].text);
        }
      } else {
        MeizuLyricsService.stopLyric();
      }
    }
  }

  void _updateLyriconState() {
    final enabled = _lyriconEnabledSignal.value;
    LyriconService.setServiceEnabled(enabled);
    
    if (enabled) {
      // When enabled, send current song and state immediately
      final song = currentSong;
      if (song != null) {
        _syncSongToLyricon(song, _lyricModel);
      }
      LyriconService.setPlaybackState(_isPlaying);
      LyriconService.updatePosition(_position.inMilliseconds);
    } else {
      // When disabled, send empty state?
      // Actually setServiceEnabled(false) handles unregistering, 
      // but we might want to ensure playback state is stopped first.
      LyriconService.setPlaybackState(false);
    }
  }

  void _syncSongToLyricon(MusicEntity song, flmodel.LyricModel? model) {
    // If user enabled force karaoke for Lyricon, we might need to re-parse or use the model differently
    // Actually, `_rebuildLyricsOutputs` already builds a model based on app-wide karaoke setting.
    // If app-wide karaoke is OFF, but Lyricon force karaoke is ON, we need a separate model for Lyricon.
    // Or simpler: if Lyricon force karaoke is ON, and current model has no words, try to generate them.

    flmodel.LyricModel? lyriconModel = model;
    final lyriconForceKaraoke = _lyriconForceKaraokeSignal.value;
    
    // Check if we need to regenerate model for Lyricon (only if raw lyrics exist)
    if (lyriconForceKaraoke && _rawLyrics != null && _rawLyrics!.isNotEmpty) {
       // If current model doesn't have words, or we want to ensure simulated words:
       // We can just rebuild a temporary model with predictDuration=true
       // Optimization: if _lyricsKaraokeEnabledSignal is already true, 'model' is already built with prediction.
       if (!_lyricsKaraokeEnabledSignal.value) {
          lyriconModel = LyricsParser.buildModelFromRaw(_rawLyrics!, predictDuration: true);
       }
    }

    final hideTranslation = _lyriconHideTranslationSignal.value;
    
    LyriconService.setSong(
      song, 
      lyriconModel, 
      hideTranslation: hideTranslation,
    );

    if (lyriconModel != null) {
       final hasTranslation = !hideTranslation && lyriconModel.lines.any((l) => l.translation != null && l.translation!.isNotEmpty);
       LyriconService.setDisplayTranslation(hasTranslation);
    } else {
       LyriconService.setDisplayTranslation(false);
    }
  }



  void _rebuildLyricsOutputs() {
    if (_lyricsLines.isEmpty) {
      _lyrics = null;
      _lyricsTranslation = null;
      _rawLyrics = null;
      _lyricModel = null;
      return;
    }
    _lyrics = LyricsParser.reconstructLrc(_lyricsLines, translation: false);
    _lyricsTranslation = LyricsParser.reconstructLrc(_lyricsLines, translation: true);
    
    // Karaoke Mode Logic:
    // If enabled (Force Karaoke): 
    //   - Parse raw if available.
    //   - If raw has karaoke tags, use them.
    //   - If raw has NO karaoke tags, simulate words (predictDuration: true).
    // If disabled (Normal Mode):
    //   - Parse raw if available.
    //   - If raw has karaoke tags, use them.
    //   - If raw has NO karaoke tags, DO NOT simulate words (predictDuration: false).
    
    final forceKaraoke = _lyricsKaraokeEnabledSignal.value;
    final raw = _rawLyrics;
    flmodel.LyricModel model;

    if (raw != null && raw.trim().isNotEmpty) {
      model = LyricsParser.buildModelFromRaw(raw, predictDuration: forceKaraoke);
      
      // Fallback logic check:
      // If we are in forced mode, buildModelFromRaw should have generated words.
      // If it didn't (e.g. text too long or other issues), check if we need fallback.
      final hasWords = model.lines.any((l) => l.words != null && l.words!.isNotEmpty);
      
      if (!hasWords && forceKaraoke) {
         // Try building from lines as a fallback if raw parsing failed to generate words
         // But buildModelFromRaw already handles standard lines too.
         // Only switch to buildModel if we suspect _lyricsLines has better data (e.g. parsed externally).
         // For now, let's keep the original fallback pattern but simplified.
         final fallbackModel = LyricsParser.buildModel(_lyricsLines, predictDuration: true);
         if (fallbackModel.lines.any((l) => l.words != null && l.words!.isNotEmpty)) {
           model = fallbackModel;
         }
      }
    } else {
      model = LyricsParser.buildModel(_lyricsLines, predictDuration: forceKaraoke);
    }
    _lyricModel = model;
    
    final song = currentSong;
    if (song != null && _lyriconEnabledSignal.value) {
      LyriconService.setSong(song, _lyricModel);
      final hasTranslation = _lyricModel?.lines.any((l) => l.translation != null && l.translation!.isNotEmpty) ?? false;
      LyriconService.setDisplayTranslation(hasTranslation);
    }
  }

  void insertNext(List<MusicEntity> songs) {
    if (songs.isEmpty) return;
    if (_queue.isEmpty) {
      playList(songs);
      return;
    }
    final insertIndex = _currentIndex + 1;
    _queue.insertAll(insertIndex, songs);
    AppAudioService.updateQueue(_queue);
    _bump(queueTick);
    _persistPlaybackState(force: true);
  }

  Future<void> setPlaybackThemeMode(ThemeMode mode) async {
    var value = 'system';
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      case ThemeMode.system:
        value = 'system';
        break;
    }
    await StorageUtil.setString(StorageKeys.playbackThemeMode, value);
    _playbackThemeMode = mode;
    _bump(uiTick);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _localServer.start();
    await _initPlayer();
    if (!_sessionHydrated) {
      await _restoreLastSession();
      _sessionHydrated = true;
    }
    AppAudioService.bindPlayer(this);
    if (kDebugMode) {
      debugPrint('PlayerViewModel.init done');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fix: Ensure UI syncs with current lyrics preferences in memory
      // We don't need to reload from storage (which causes delay and potential data loss),
      // just notify listeners to refresh the view with existing correct values.
      _bump(lyricsTick);
    }
  }

  Future<void> hydrateForUi() async {
    if (_sessionHydrated) return;
    await _restoreLastSession();
    _sessionHydrated = true;
  }

  Future<void> _initPlayer() async {
    final enableSoft = StorageUtil.getBoolOrDefault(StorageKeys.enableSoftDecoding);
    _player = AudioPlayer();
    
    if (kDebugMode) {
      print('Initializing Player. Force Soft Decoding: $enableSoft');
    }

    _player.positionStream.listen((p) {
      if (_hasRestoredPosition && p == Duration.zero && !_isPlaying) {
        return;
      }
      _hasRestoredPosition = false;
      _position = p;
      _updateCurrentLyricIndex();
      _ensureMediaItem();
      AppAudioService.updatePlayback(
        playing: _isPlaying,
        position: _position,
        duration: _duration,
      );
      if (_lyriconEnabledSignal.value) {
        LyriconService.updatePosition(p.inMilliseconds);
      }
      _bump(playbackTick);
      _persistPlaybackState();
    });
    
    _player.durationStream.listen((d) {
      final newDuration = d ?? Duration.zero;
      if (newDuration == Duration.zero) {
        return;
      }
      if (newDuration == _duration) {
        return;
      }
      _duration = newDuration;

      // Fix: Update duration in DB if significantly different (e.g. was 0 or 00:02)
      final song = currentSong;
      if (song != null) {
        final oldMs = song.durationMs ?? 0;
        final newMs = newDuration.inMilliseconds;
        // Update if difference is > 2 seconds or old was 0
        if (newMs > 0 && (oldMs == 0 || (newMs - oldMs).abs() > 2000)) {
           final updated = song.copyWith(durationMs: newMs);
           // Update queue immediately to reflect in UI
           if (_currentIndex >= 0 && _currentIndex < _queue.length && _queue[_currentIndex].id == song.id) {
             _queue[_currentIndex] = updated;
           }
           // Persist to DB and Library
           DatabaseHelper().updateMusic(updated).then((_) {
             LibraryViewModel().updateSongInLibrary(updated);
           }).catchError((e) {
             debugPrint('Failed to update duration: $e');
           });
        }
      }

      _ensureMediaItem();
      AppAudioService.updatePlayback(
        playing: _isPlaying,
        position: _position,
        duration: _duration,
      );
      _bump(playbackTick);
      _persistPlaybackState();
    });
    
    _player.playingStream.listen((playing) {
      _isPlaying = playing;
      _ensureMediaItem();
      AppAudioService.updatePlayback(
        playing: _isPlaying,
        position: _position,
        duration: _duration,
      );
      if (_lyriconEnabledSignal.value) {
        LyriconService.setPlaybackState(playing);
      }
      _bump(playbackTick);
    });

    _player.processingStateStream.listen((state) {
      final processingState = switch (state) {
        ProcessingState.loading => AudioProcessingState.buffering,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
        ProcessingState.idle => AudioProcessingState.ready,
      };
      _ensureMediaItem();
      AppAudioService.updatePlayback(
        playing: _isPlaying,
        position: _position,
        duration: _duration,
        processingState: processingState,
      );
      if (state == ProcessingState.completed) {
        if (_mode == PlaybackMode.single) {
          _player.seek(Duration.zero);
          _player.play();
        } else {
          next();
        }
      }
    });
  }

  void _ensureMediaItem() {
    final song = currentSong;
    if (song == null) return;
    if (_lastReportedMediaId != song.id) {
      _lastReportedMediaId = song.id;
      AppAudioService.updateCurrent(song);
    }
  }

  Future<void> updateDecodingMode() async {
    final currentIdx = _currentIndex;
    final currentPos = _position;
    final wasPlaying = _isPlaying;
    
    await _player.dispose();
    await _initPlayer();
    
    if (currentIdx >= 0 && currentIdx < _queue.length) {
       await _playCurrent(initialPosition: currentPos, autoPlay: wasPlaying);
    }
  }

  Future<void> playList(List<MusicEntity> songs, {int initialIndex = 0}) async {
    _queue = List.from(songs);
    _currentIndex = initialIndex;
    AppAudioService.updateQueue(_queue);
    await _playCurrent();
    _persistPlaybackState(force: true);
  }
  
  Future<void> playSongInQueue(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      await _playCurrent();
      _persistPlaybackState(force: true);
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      await clearQueue();
      return;
    }
    if (index < _currentIndex) {
      _currentIndex -= 1;
    }
    if (removingCurrent) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      AppAudioService.updateQueue(_queue);
      await _playCurrent(autoPlay: _isPlaying);
      _persistPlaybackState(force: true);
      return;
    }
    AppAudioService.updateQueue(_queue);
    _bump(queueTick);
    _persistPlaybackState(force: true);
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex += 1;
    }
    AppAudioService.updateQueue(_queue);
    _bump(queueTick);
    _persistPlaybackState(force: true);
  }

  Future<void> _playCurrent({Duration? initialPosition, bool autoPlay = true}) async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final requestId = ++_playRequestId;
    final startIndex = _currentIndex;
    
    // Clear artwork immediately to prevent showing previous song's cover
    _artwork = null;
    _lyrics = null;
    _lyricsTranslation = null;
    _rawLyrics = null;
    _lyricModel = null;
    _lyricsLines = [];
    _currentLyricIndex = -1;
    _bump(queueTick);
    _bump(lyricsTick);
    _bump(playbackTick);

    var song = _queue[startIndex];
    if (_lyriconEnabledSignal.value) {
      LyriconService.setSong(song, null);
      LyriconService.setDisplayTranslation(false);
    }
    if (_meizuLyricsEnabledSignal.value) {
      MeizuLyricsService.stopLyric();
    }

    if (kDebugMode) {
      debugPrint('PlayerViewModel.playCurrent ${song.title} autoPlay=$autoPlay');
    }
    bool isStale() {
      if (requestId != _playRequestId) return true;
      if (startIndex != _currentIndex) return true;
      if (startIndex < 0 || startIndex >= _queue.length) return true;
      return _queue[startIndex].id != song.id;
    }
    
    // Hydrate song from database to check for cached metadata (especially for cloud songs)
    if (!song.isLocal) {
       final db = DatabaseHelper();
       final cachedSong = await db.getSongById(song.id);
       if (isStale()) return;
       if (cachedSong != null) {
         // Merge cached paths/lyrics into current song entity
         song = song.copyWith(
           localCoverPath: cachedSong.localCoverPath,
           localLyricPath: cachedSong.localLyricPath,
           lyrics: cachedSong.lyrics,
         );
         // Update queue with hydrated song
         if (!isStale()) {
           _queue[startIndex] = song;
           AppAudioService.updateQueue(_queue);
         }
       }
    }

    if (isStale()) return;
    _title = song.title;
    _artist = song.artist;
    _artwork = song.artwork;
    _setDominantColorFromArtwork(_artwork);
    StorageUtil.setString(StorageKeys.lastPlayedSongId, song.id);
    AppAudioService.updateCurrent(song);
    
    _isPlaying = autoPlay;
    AppAudioService.updatePlayback(
      playing: _isPlaying,
      position: Duration.zero,
      duration: _duration,
      processingState: AudioProcessingState.buffering,
    );

    final storedLyrics = song.lyrics;
    if (storedLyrics != null && storedLyrics.trim().isNotEmpty) {
      _rawLyrics = storedLyrics;
      _lyricsLines = _parseLyricsLines(storedLyrics);
      _rebuildLyricsOutputs();
    }
    _bump(queueTick);
    _bump(lyricsTick);
    
    if (song.uri != null) {
      if (song.isLocal) {
        _loadLocalMetadata(song);
      } else {
        final cachedLyrics = _webDavLyricsCache[song.id];
        if (cachedLyrics != null && cachedLyrics.isNotEmpty) {
          _rawLyrics = cachedLyrics;
          _lyricsLines = _parseLyricsLines(cachedLyrics);
          _rebuildLyricsOutputs();
        }
        final cachedCover = _webDavCoverCache[song.id];
        if (cachedCover != null && cachedCover.isNotEmpty) {
          _artwork = cachedCover;
          _setDominantColorFromArtwork(cachedCover);
        }
        _bump(queueTick);
      }
    }

    if (_artwork == null && song.localCoverPath != null) {
      Future.microtask(() async {
        try {
          final file = File(song.localCoverPath!);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length && _queue[_currentIndex].id == song.id) {
              _artwork = bytes;
              _setDominantColorFromArtwork(bytes);
              _bump(queueTick);
            }
          }
        } catch (_) {}
      });
    }

    if (song.uri != null) {
      try {
        final parsedUri = _getSafeUri(song.uri!);
        if (parsedUri == null) {
           if (kDebugMode) print('Invalid URI: ${song.uri}');
           return;
        }
        if (isStale()) return;

        AudioSource source;
        if (song.isLocal) {
          source = AudioSource.file(song.uri!);
        } else {
          final cacheManager = CacheManager();
          final cachePath = await cacheManager.getAudioCachePath();
          final ext = _getExtensionFromUri(parsedUri);
          final cacheFile = File('$cachePath/${song.id.hashCode}.$ext'); 
          final completeFile = File('${cacheFile.path}.complete');

          if (await cacheFile.exists() && await completeFile.exists()) {
            source = AudioSource.file(cacheFile.path);
          } else {
            var effectiveSong = song;
            if (!song.isLocal && song.sourceId != null) {
               final headers = LibraryViewModel().getHeadersForSource(song.sourceId!);
               if (headers != null && headers.isNotEmpty) {
                  effectiveSong = song.copyWith(headers: headers);
               }
            }

            final localUri = await _localServer.registerSource(effectiveSong, cacheFile);
            source = AudioSource.uri(localUri, headers: effectiveSong.headers);
          }
          
          final hasLyrics = song.lyrics != null && song.lyrics!.trim().isNotEmpty;
          final hasCover = song.localCoverPath != null;
          if (!hasLyrics || !hasCover) {
            fetchRemoteEmbeddedTags(song);
          }
        }
        
        if (isStale()) return;
        await _player.setAudioSource(
          source,
          initialPosition: initialPosition,
        );
        if (isStale()) return;
        if (autoPlay) {
          await _player.play();
        } else {
          await _player.pause();
        }
        AppAudioService.updatePlayback(
          playing: _isPlaying,
          position: _position,
          duration: _duration,
          processingState: AudioProcessingState.ready,
        );
        
        // Trigger WebDAV fetch logic
        if (!song.isLocal) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (_currentIndex >= 0 && _currentIndex < _queue.length && _queue[_currentIndex].id == song.id) {
              _fetchWebDavMetadata(song);
            }
          });
          
          final limitMb = StorageUtil.getIntOrDefault(
            StorageKeys.cacheSizeLimitMb,
            defaultValue: 1024,
          );
          if (limitMb > 0) {
            final cacheManager = CacheManager();
            final maxBytes = limitMb * 1024 * 1024;
            Future.delayed(const Duration(seconds: 5), () {
              cacheManager.trimAllCache(
                maxBytes,
                excludePaths: {}, 
              );
            });
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error playing ${song.title}: $e');
      }
    }
  }

  void _persistPlaybackState({bool force = false}) {
    if (!_sessionHydrated) {
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastPersistedStateTime).inMilliseconds < 1000) {
      return;
    }
    _lastPersistedStateTime = now;
    if (_queue.isEmpty || _currentIndex < 0 || _currentIndex >= _queue.length) {
      StorageUtil.remove(StorageKeys.lastPlaybackQueue);
      StorageUtil.remove(StorageKeys.lastPlaybackIndex);
      StorageUtil.remove(StorageKeys.lastPlaybackPositionMs);
      StorageUtil.remove(StorageKeys.lastPlaybackDurationMs);
      return;
    }
    final ids = _queue.map((e) => e.id).toList();
    final rawQueue = jsonEncode(ids);
    StorageUtil.setString(StorageKeys.lastPlaybackQueue, rawQueue);
    StorageUtil.setInt(StorageKeys.lastPlaybackIndex, _currentIndex);
    StorageUtil.setInt(
      StorageKeys.lastPlaybackPositionMs,
      _position.inMilliseconds,
    );
    StorageUtil.setInt(
      StorageKeys.lastPlaybackDurationMs,
      _duration.inMilliseconds,
    );
  }

  Future<void> _restoreLastSession() async {
    final rawQueue = StorageUtil.getString(StorageKeys.lastPlaybackQueue);
    if (rawQueue == null || rawQueue.isEmpty) {
      await _restoreLastSong();
      return;
    }
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(rawQueue) as List<dynamic>;
    } catch (_) {
      await _restoreLastSong();
      return;
    }
    final ids = decoded.whereType<String>().toList();
    if (ids.isEmpty) {
      await _restoreLastSong();
      return;
    }
    final db = DatabaseHelper();
    final songs = await db.getSongsByIds(ids);
    if (songs.isEmpty) {
      await _restoreLastSong();
      return;
    }
    var index = StorageUtil.getIntOrDefault(
      StorageKeys.lastPlaybackIndex,
      defaultValue: 0,
    );
    if (index < 0) index = 0;
    if (index >= songs.length) index = songs.length - 1;
    final posMs = StorageUtil.getIntOrDefault(
      StorageKeys.lastPlaybackPositionMs,
      defaultValue: 0,
    );
    final durMsOverride = StorageUtil.getIntOrDefault(
      StorageKeys.lastPlaybackDurationMs,
      defaultValue: 0,
    );
    final position =
        posMs > 0 ? Duration(milliseconds: posMs) : Duration.zero;

    _queue = songs;
    _currentIndex = index;
    _position = position;
    _hasRestoredPosition = position > Duration.zero;

    final song = _queue[_currentIndex];
    _title = song.title;
    _artist = song.artist;
    _artwork = song.artwork;
    final baseDuration = song.durationMs == null
        ? Duration.zero
        : Duration(milliseconds: song.durationMs!);
    _duration = durMsOverride > 0
        ? Duration(milliseconds: durMsOverride)
        : baseDuration;
    _isPlaying = false;
    _setDominantColorFromArtwork(_artwork);

    final storedLyrics = song.lyrics;
    if (storedLyrics != null && storedLyrics.trim().isNotEmpty) {
      _rawLyrics = storedLyrics;
      _lyricsLines = _parseLyricsLines(storedLyrics);
      _rebuildLyricsOutputs();
      _updateCurrentLyricIndex();
    }

    _bump(queueTick);
    _bump(lyricsTick);
    _bump(playbackTick);
    if (_artwork == null && song.localCoverPath != null) {
      Future.microtask(() async {
        try {
          final file = File(song.localCoverPath!);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty &&
                _currentIndex >= 0 &&
                _currentIndex < _queue.length &&
                _queue[_currentIndex].id == song.id) {
              _artwork = bytes;
              _setDominantColorFromArtwork(bytes);
              _bump(queueTick);
            }
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _restoreLastSong() async {
    final songId = StorageUtil.getString(StorageKeys.lastPlayedSongId);
    if (songId == null || songId.isEmpty) return;
    final song = await DatabaseHelper().getSongById(songId);
    if (song == null) return;
    _queue = [song];
    _currentIndex = 0;
    _title = song.title;
    _artist = song.artist;
    _artwork = song.artwork;
    _duration = song.durationMs == null
        ? Duration.zero
        : Duration(milliseconds: song.durationMs!);
    _position = Duration.zero;
    _isPlaying = false;
    _setDominantColorFromArtwork(_artwork);

    final storedLyrics = song.lyrics;
    if (storedLyrics != null && storedLyrics.trim().isNotEmpty) {
      _rawLyrics = storedLyrics;
      _lyricsLines = _parseLyricsLines(storedLyrics);
      _rebuildLyricsOutputs();
      _updateCurrentLyricIndex();
    }

    _bump(queueTick);
    _bump(lyricsTick);
    _bump(playbackTick);
    if (_artwork == null && song.localCoverPath != null) {
      Future.microtask(() async {
        try {
          final file = File(song.localCoverPath!);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty &&
                _currentIndex == 0 &&
                _queue.isNotEmpty &&
                _queue.first.id == song.id) {
              _artwork = bytes;
              _setDominantColorFromArtwork(bytes);
              _bump(queueTick);
            }
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _loadLocalMetadata(MusicEntity song) async {
    if (song.tagsParsed) return;
    Future.microtask(() async {
      try {
        final probe = TagProbeService();
        final result = await probe.probeSongDedup(song);
        if (result == null) return;
        final title = result.title?.trim();
        final artist = result.artist?.trim();
        final album = result.album?.trim();
        final artwork = result.artwork;
        String? localCoverPath = song.localCoverPath;
        if (artwork != null && artwork.isNotEmpty) {
          final needsCover = localCoverPath == null ||
              localCoverPath.isEmpty ||
              !(await File(localCoverPath).exists());
          if (needsCover) {
            final cache = CacheManager();
            final coverFile = await cache.saveCoverImage(song.id, artwork);
            if (coverFile != null) {
              localCoverPath = coverFile.path;
            }
          }
        }
        final updatedSong = song.copyWith(
          title: title?.isNotEmpty == true ? title! : song.title,
          artist: artist?.isNotEmpty == true ? artist! : song.artist,
          album: album?.isNotEmpty == true ? album : song.album,
          artwork: artwork?.isNotEmpty == true ? artwork : song.artwork,
          localCoverPath: localCoverPath,
          tagsParsed: true,
        );
        final isCurrentSong = _currentIndex >= 0 &&
            _currentIndex < _queue.length &&
            _queue[_currentIndex].id == song.id;
        if (isCurrentSong) {
          bool changed = false;
          if (_title != updatedSong.title) {
            _title = updatedSong.title;
            changed = true;
          }
          if (_artist != updatedSong.artist) {
            _artist = updatedSong.artist;
            changed = true;
          }
          if (artwork != null &&
              artwork.isNotEmpty &&
              (_artwork == null || _artwork!.isEmpty)) {
            _artwork = artwork;
            _setDominantColorFromArtwork(artwork);
            changed = true;
          }
          _queue[_currentIndex] = updatedSong;
          AppAudioService.updateCurrent(updatedSong);
          if (changed) {
            _bump(queueTick);
          }
        }
        final db = DatabaseHelper();
        await db.insertSong(updatedSong);
        LibraryViewModel().updateSongInLibrary(updatedSong);
      } catch (e) {
        if (kDebugMode) print('Error reading lyrics: $e');
      }
    });
  }

  Future<void> _fetchWebDavMetadata(MusicEntity song) async {
    if (_webDavMetadataLoading.contains(song.id)) return;
    final blockedUntil = _webDavMetadataBlockedUntil[song.id];
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) return;
    final lastFetch = _webDavMetadataLastFetch[song.id];
    if (lastFetch != null &&
        DateTime.now().difference(lastFetch) < const Duration(seconds: 6)) {
      return;
    }
    _webDavMetadataLoading.add(song.id);
    _webDavMetadataLastFetch[song.id] = DateTime.now();
    if (kDebugMode) {
      debugPrint('WebDAV: Starting fetch for ${song.title} (ID: ${song.id})');
    }
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    
    final uriStr = song.uri!;
    final uri = Uri.tryParse(uriStr);
    if (uri == null) return;

    final sourceHeaders = (!song.isLocal && song.sourceId != null) 
        ? LibraryViewModel().getHeadersForSource(song.sourceId!)
        : null;
    final requestHeaders = sourceHeaders ?? song.headers;
    
    bool isCurrentSong() =>
        _currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _queue[_currentIndex].id == song.id;

    final path = uri.path;
    final dotIndex = path.lastIndexOf('.');
    final lyricsState = _webDavLyricsState[song.id] ?? _MetaFetchState.idle;
    final needLyrics = lyricsState == _MetaFetchState.idle &&
        !_webDavLyricsCache.containsKey(song.id);
    
    final coverState = _webDavCoverState[song.id] ?? _MetaFetchState.idle;
    final needCover = coverState == _MetaFetchState.idle &&
        !_webDavCoverCache.containsKey(song.id);

    if (!needLyrics && !needCover) {
      _webDavMetadataLoading.remove(song.id);
      return;
    }

    final futures = <Future>[];

    if (dotIndex != -1 && needLyrics) {
      _webDavLyricsState[song.id] = _MetaFetchState.fetching;
      final lrcPath = '${path.substring(0, dotIndex)}.lrc';
      final lrcUri = uri.replace(path: lrcPath);
      
      futures.add(_fetchWithManualRedirect(
        dio,
        lrcUri,
        Options(
          headers: requestHeaders,
          responseType: ResponseType.plain,
        ),
      ).then((response) async {
        if (response.statusCode == 403 || response.statusCode == 401) {
           _webDavLyricsState[song.id] = _MetaFetchState.failed;
           return;
        }
        if (response.statusCode == 200 && response.data != null) {
           final lrcContent = response.data.toString();
           final normalized = _dedupeLyricsContent(lrcContent);
           if (_isValidLrc(normalized)) {
             if (isCurrentSong()) {
              _rawLyrics = normalized;
               _lyricsLines = _parseLyricsLines(normalized);
               _rebuildLyricsOutputs();
               _webDavLyricsCache[song.id] = normalized;
               _webDavLyricsState[song.id] = _MetaFetchState.success;
               _bump(lyricsTick);
               final updatedSong = song.copyWith(lyrics: normalized);
               if (_currentIndex >= 0 && _currentIndex < _queue.length) {
                 _queue[_currentIndex] = updatedSong;
               }
               final db = DatabaseHelper();
               await db.insertSong(updatedSong);
               LibraryViewModel().updateSongInLibrary(updatedSong);
             }
           } else {
             _webDavLyricsState[song.id] = _MetaFetchState.failed;
             _webDavLyricsCache[song.id] = '';
           }
        } else {
          _webDavLyricsState[song.id] = _MetaFetchState.failed;
          _webDavLyricsCache[song.id] = '';
        }
      }).catchError((e) {
        _webDavLyricsState[song.id] = _MetaFetchState.failed;
      }),
      );
    }

    if (needCover) {
      _webDavCoverState[song.id] = _MetaFetchState.fetching;
      final parentPath = path.substring(0, path.lastIndexOf('/') + 1);
      final baseUri = uri.replace(path: parentPath);
      
      final coverNames = [
        'cover.jpg', 'cover.jpeg', 'cover.png', 
        'folder.jpg', 'folder.jpeg', 'folder.png', 
        'front.jpg', 'front.jpeg', 'front.png',
      ];
      if (dotIndex != -1) {
         final name = Uri.decodeComponent(path.substring(path.lastIndexOf('/') + 1, dotIndex));
         coverNames.add('$name.jpg');
         coverNames.add('$name.png');
         coverNames.add('$name.jpeg');
      }

      futures.add(Future(() async {
        for (final name in coverNames) {
          if (_currentIndex >=0 && _currentIndex < _queue.length && _queue[_currentIndex].id != song.id) break;
          final coverUri = baseUri.resolve(Uri.encodeComponent(name)); 
          try {
            final response = await _fetchWithManualRedirect(
              dio,
              coverUri,
              Options(
                headers: requestHeaders,
                responseType: ResponseType.bytes,
              ),
            );
            if (response.statusCode == 403 || response.statusCode == 401) {
               continue;
            }
            if (response.statusCode == 200 && response.data != null) {
               final bytes = Uint8List.fromList(response.data as List<int>);
               if (bytes.isNotEmpty && _isValidImage(bytes)) {
                 if (isCurrentSong()) {
                     _artwork = bytes;
                     _setDominantColorFromArtwork(bytes);
                     _webDavCoverCache[song.id] = bytes;
                     _webDavCoverState[song.id] = _MetaFetchState.success;
                     _bump(queueTick);
                     
                     final cacheManager = CacheManager();
                     final coverFile = await cacheManager.saveCoverImage(song.id, bytes);
                     if (coverFile != null) {
                        final newSong = song.copyWith(localCoverPath: coverFile.path);
                        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
                           _queue[_currentIndex] = newSong;
                        }
                        final db = DatabaseHelper();
                        await db.insertSong(newSong);
                        LibraryViewModel().updateSongInLibrary(newSong);
                     }
                  }
                  return; 
               }
            }
          } catch (e) {
            // ignore
          }
        }
        _webDavCoverState[song.id] = _MetaFetchState.failed;
      }),
      );
    }

    await Future.wait(futures);
    _webDavMetadataLoading.remove(song.id);
  }

  bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return true;
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
    return false;
  }

  bool _isValidLrc(String content) {
    if (content.trim().isEmpty) return false;
    if (content.contains('<html') || content.contains('<!DOCTYPE') || content.contains('<head>')) return false;
    return true;
  }

  Future<Map<String, dynamic>> debugRunMetadataFlow(MusicEntity song) async {
    _queue = [song];
    _currentIndex = 0;
    _title = song.title;
    _artist = song.artist;
    _lyrics = null;
    _lyricsTranslation = null;
    _rawLyrics = null;
    _lyricModel = null;
    _lyricsLines = [];
    _artwork = song.artwork;
    _bump(queueTick);
    _bump(lyricsTick);
    _bump(playbackTick);
    final embeddedSuccess = await fetchRemoteEmbeddedTags(song);
    await _fetchWebDavMetadata(song);
    final lyrics = _lyrics ?? _webDavLyricsCache[song.id];
    return {
      'title': _title,
      'artist': _artist,
      'album': song.album,
      'lyrics': lyrics,
      'lyricsLines': _lyricsLines.length,
      'artworkBytes': _artwork?.length ?? 0,
      'lyricsCached': _webDavLyricsCache[song.id]?.length ?? 0,
      'coverCached': _webDavCoverCache[song.id]?.length ?? 0,
      'embeddedSuccess': embeddedSuccess,
    };
  }

  String _dedupeLyricsContent(String content) {
    final normalized = content.replaceFirst(RegExp('^\uFEFF'), '');
    final collapsed = _collapseRepeatedLrc(normalized);
    return _collapseAdjacentLines(collapsed);
  }

  List<LyricLine> _parseLyricsLines(String content) {
    return LyricsParser.parseLrc(content);
  }

  String _collapseAdjacentLines(String content) {
    if (content.isEmpty) return content;
    final lines = content.split(RegExp(r'\r?\n'));
    if (lines.length < 2) return content;
    
    final deduped = <String>[];
    String? lastLine;
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        deduped.add(line); 
        lastLine = null;
        continue;
      }
      if (trimmed == lastLine) {
        continue;
      }
      deduped.add(line);
      lastLine = trimmed;
    }
    return deduped.join('\n');
  }

  String _collapseRepeatedLrc(String content) {
    final trimmed = content.trim().replaceFirst(RegExp('^\uFEFF'), '');
    if (trimmed.isEmpty) return content;
    final lines = trimmed.split(RegExp(r'\r?\n'));
    final checkLines = lines.map((e) => e.trim()).toList();
    
    final n = lines.length;
    if (n < 2) return content;
    final pi = List<int>.filled(n, 0);
    for (int i = 1; i < n; i++) {
      var j = pi[i - 1];
      while (j > 0 && checkLines[i] != checkLines[j]) {
        j = pi[j - 1];
      }
      if (checkLines[i] == checkLines[j]) {
        j++;
      }
      pi[i] = j;
    }
    final period = n - pi[n - 1];
    if (period > 0 && n % period == 0 && n ~/ period >= 2) {
      return lines.sublist(0, period).join('\n');
    }
    return content;
  }

  String _getExtensionFromUri(Uri uri) {
    final path = uri.path;
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot >= path.length - 1) return 'mp3';
    final ext = path.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'mp3' : ext;
  }

  bool _isMeaningfulTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return false;
    if (t == '未知标题') return false;
    return true;
  }

  bool _isMeaningfulArtist(String artist) {
    final a = artist.trim();
    if (a.isEmpty) return false;
    if (a == '未知艺术家') return false;
    return true;
  }

  Future<bool> _hasCachedCover(MusicEntity song) async {
    final path = song.localCoverPath?.trim() ?? '';
    if (path.isNotEmpty && await File(path).exists()) return true;
    return CacheManager().hasCover(song.id);
  }

  bool _hasCachedLyrics(MusicEntity song) {
    if ((song.lyrics ?? '').trim().isNotEmpty) return true;
    final cached = _webDavLyricsCache[song.id];
    return cached != null && cached.trim().isNotEmpty;
  }

  bool _isMetadataCompleteForScrape(
    MusicEntity song, {
    required bool hasCover,
    required bool hasLyrics,
  }) {
    final hasTitle = _isMeaningfulTitle(song.title);
    final hasArtist = _isMeaningfulArtist(song.artist);
    final hasAlbum = (song.album ?? '').trim().isNotEmpty;
    final hasDuration = (song.durationMs ?? 0) > 0;
    final hasBasics = hasTitle && hasArtist && hasAlbum;
    final hasExtras = hasCover || hasLyrics || hasDuration;
    return hasBasics && hasExtras;
  }

  Future<bool> _shouldSkipTagProbe(MusicEntity song) async {
    final hasCover = await _hasCachedCover(song);
    final hasLyrics = _hasCachedLyrics(song);
    return _isMetadataCompleteForScrape(
      song,
      hasCover: hasCover,
      hasLyrics: hasLyrics,
    );
  }

  Future<bool> fetchRemoteEmbeddedTags(MusicEntity song, {String? ext, bool force = false}) async {
    if (_isFetchingTags) return false;
    if (!force) {
      final skip = await _shouldSkipTagProbe(song);
      if (skip) return true;
    }
    _isFetchingTags = true;
    _bump(tagTick);

    bool success = false;
    try {
      final probe = TagProbeService();
      final result = await probe.probeSong(song);
      if (result != null) {
        final cacheManager = CacheManager();
        final Uint8List? artworkBytes = result.artwork;
        final String? normalizedLyrics = result.lyrics;
        final String? newTitle = result.title;
        final String? newArtist = result.artist;
        final String? newAlbum = result.album;
        String? localCoverPath = song.localCoverPath;
        
        // Fix: Verify existing local cover path validity
        if (localCoverPath != null) {
          final file = File(localCoverPath);
          if (!await file.exists()) {
            localCoverPath = null;
          }
        }

        if (artworkBytes != null && artworkBytes.isNotEmpty) {
          final coverFile = await cacheManager.saveCoverImage(song.id, artworkBytes);
          localCoverPath = coverFile?.path ?? localCoverPath;
          _webDavCoverCache[song.id] = artworkBytes;
          _webDavCoverState[song.id] = _MetaFetchState.success;
        }
        if (normalizedLyrics != null && normalizedLyrics.trim().isNotEmpty) {
          final currentCached = _webDavLyricsCache[song.id];
          if (currentCached != normalizedLyrics) {
            _webDavLyricsCache[song.id] = normalizedLyrics;
            _webDavLyricsState[song.id] = _MetaFetchState.success;
          }
        }
        final updatedSong = song.copyWith(
          title: newTitle?.isNotEmpty == true ? newTitle : song.title,
          artist: newArtist?.isNotEmpty == true ? newArtist : song.artist,
          album: newAlbum?.isNotEmpty == true ? newAlbum : song.album,
          artwork: artworkBytes?.isNotEmpty == true ? artworkBytes : song.artwork,
          localCoverPath: localCoverPath,
          lyrics: normalizedLyrics ?? song.lyrics,
          durationMs: result.duration?.inMilliseconds ?? song.durationMs,
        );
        
        bool hasChanges = false;
        if (updatedSong.title != song.title) hasChanges = true;
        if (updatedSong.artist != song.artist) hasChanges = true;
        if (updatedSong.album != song.album) hasChanges = true;
        if (updatedSong.localCoverPath != song.localCoverPath) hasChanges = true;
        if (updatedSong.lyrics != song.lyrics) hasChanges = true;
        if (updatedSong.durationMs != song.durationMs) hasChanges = true;
        
        if (hasChanges) {
          if (_currentIndex >= 0 &&
              _currentIndex < _queue.length &&
              _queue[_currentIndex].id == song.id) {
            bool uiChanged = false;
            if (newTitle != null && newTitle.isNotEmpty && _title != newTitle) {
              _title = newTitle;
              uiChanged = true;
            }
            if (newArtist != null && newArtist.isNotEmpty && _artist != newArtist) {
              _artist = newArtist;
              uiChanged = true;
            }
            if (artworkBytes != null && artworkBytes.isNotEmpty) {
              _artwork = artworkBytes;
              _setDominantColorFromArtwork(artworkBytes);
              uiChanged = true;
            }
            if (normalizedLyrics != null) {
              final newLines = _parseLyricsLines(normalizedLyrics);
              _rawLyrics = normalizedLyrics;
              _lyricsLines = newLines;
              _rebuildLyricsOutputs();
              uiChanged = true;
            }
            if (uiChanged) {
              _bump(queueTick);
              _bump(lyricsTick);
            }
          }
          final queueIndex = _queue.indexWhere((s) => s.id == song.id);
          if (queueIndex >= 0) {
            _queue[queueIndex] = updatedSong;
          }
          final db = DatabaseHelper();
          await db.insertSong(updatedSong);
          LibraryViewModel().updateSongInLibrary(updatedSong);
          success = true;
        }
      }
    } catch (_) {}
    _isFetchingTags = false;
    _bump(tagTick);
    return success;
  }

  Future<void> setSourceUri(Uri uri, {String? title, String? artist, Map<String, String>? headers}) async {
    final song = MusicEntity(
      id: uri.toString(),
      title: title ?? 'Unknown',
      artist: artist ?? 'Unknown',
      uri: uri.toString(),
      isLocal: !uri.isScheme('http') && !uri.isScheme('https'),
      headers: headers,
    );
    playList([song]);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_mode == PlaybackMode.shuffle) {
      if (_queue.length == 1) {
        _currentIndex = 0;
      } else {
        var idx = _currentIndex;
        while (idx == _currentIndex) {
          idx = _random.nextInt(_queue.length);
        }
        _currentIndex = idx;
      }
    } else {
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
    }
    await _playCurrent();
    _persistPlaybackState(force: true);
  }
  
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_mode == PlaybackMode.shuffle) {
      if (_queue.length == 1) {
        _currentIndex = 0;
      } else {
        var idx = _currentIndex;
        while (idx == _currentIndex) {
          idx = _random.nextInt(_queue.length);
        }
        _currentIndex = idx;
      }
    } else {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = _queue.length - 1;
      }
    }
    await _playCurrent();
    _persistPlaybackState(force: true);
  }

  Future<void> play() async {
    final hasSource = _player.audioSource != null;
    final song = currentSong;
    if (!hasSource && song != null) {
      final initial =
          _position > Duration.zero ? _position : null;
      await _playCurrent(initialPosition: initial, autoPlay: true);
      return;
    }
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
    _persistPlaybackState(force: true);
  }

  Future<void> clearQueue() async {
    _queue = [];
    _currentIndex = -1;
    _lastReportedMediaId = null;
    _title = null;
    _artist = null;
    _artwork = null;
    _lyrics = null;
    _lyricsTranslation = null;
    _rawLyrics = null;
    _lyricModel = null;
    _lyricsLines = [];
    _currentLyricIndex = -1;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    if (_initialized) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    StorageUtil.remove(StorageKeys.lastPlaybackQueue);
    StorageUtil.remove(StorageKeys.lastPlaybackIndex);
    StorageUtil.remove(StorageKeys.lastPlaybackPositionMs);
    AppAudioService.updateQueue(_queue);
    AppAudioService.updateCurrent(null);
    AppAudioService.updatePlayback(
      playing: false,
      position: Duration.zero,
      duration: Duration.zero,
      processingState: AudioProcessingState.ready,
    );
    _bump(queueTick);
    _bump(lyricsTick);
    _bump(playbackTick);
  }

  Future<void> playNextFromLibrary(MusicEntity song) async {
    if (_queue.isEmpty || currentSong == null) {
      playList([song]);
      return;
    }
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    var insertIndex = _currentIndex + 1;
    if (existingIndex >= 0) {
      final item = _queue.removeAt(existingIndex);
      if (existingIndex < _currentIndex) {
        _currentIndex -= 1;
        insertIndex = _currentIndex + 1;
      }
      if (insertIndex > _queue.length) insertIndex = _queue.length;
      _queue.insert(insertIndex, item);
    } else {
      if (insertIndex > _queue.length) insertIndex = _queue.length;
      _queue.insert(insertIndex, song);
    }
    AppAudioService.updateQueue(_queue);
    _persistPlaybackState(force: true);
    _bump(queueTick);
  }

  Future<void> addToQueueFromLibrary(MusicEntity song) async {
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    if (existingIndex >= 0) {
      final item = _queue.removeAt(existingIndex);
      _queue.add(item);
    } else {
      _queue.add(song);
    }
    AppAudioService.updateQueue(_queue);
    _persistPlaybackState(force: true);
    _bump(queueTick);
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    _updateCurrentLyricIndex();
    _persistPlaybackState(force: true);
  }

  void _setDominantColorFromArtwork(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      _dominantColor = const ui.Color(0xFF1A1A1A);
      return;
    }
    final currentBytes = bytes;
    Future.microtask(() async {
      final color = await _extractDominantColor(currentBytes);
      if (!identical(_artwork, currentBytes)) return;
      _dominantColor = color;
      _bump(queueTick);
    });
  }

  Future<ui.Color> _extractDominantColor(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return const ui.Color(0xFF1A1A1A);
      final pixels = data.buffer.asUint8List();
      final buckets = <int, _ColorBucket>{};
      int totalR = 0;
      int totalG = 0;
      int totalB = 0;
      int totalCount = 0;
      for (int i = 0; i + 3 < pixels.length; i += 16) {
        final a = pixels[i + 3];
        if (a < 128) continue;
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        final sum = r + g + b;
        if (sum < 40 || sum > 740) continue;
        totalR += r;
        totalG += g;
        totalB += b;
        totalCount++;
        final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
        final bucket = buckets[key];
        if (bucket == null) {
          buckets[key] = _ColorBucket(1, r, g, b);
        } else {
          bucket.count++;
          bucket.r += r;
          bucket.g += g;
          bucket.b += b;
        }
      }
      if (buckets.isEmpty) {
        if (totalCount == 0) return const ui.Color(0xFF1A1A1A);
        return ui.Color.fromARGB(
          255,
          (totalR ~/ totalCount).clamp(0, 255),
          (totalG ~/ totalCount).clamp(0, 255),
          (totalB ~/ totalCount).clamp(0, 255),
        );
      }
      _ColorBucket? best;
      for (final bucket in buckets.values) {
        if (best == null || bucket.count > best.count) {
          best = bucket;
        }
      }
      if (best == null || best.count == 0) {
        return const ui.Color(0xFF1A1A1A);
      }
      return ui.Color.fromARGB(
        255,
        (best.r ~/ best.count).clamp(0, 255),
        (best.g ~/ best.count).clamp(0, 255),
        (best.b ~/ best.count).clamp(0, 255),
      );
    } catch (_) {
      return const ui.Color(0xFF1A1A1A);
    }
  }

  void _updateCurrentLyricIndex() {
    final timed = _lyricsLines.where((e) => e.time != null).toList();
    if (timed.isEmpty) {
      if (_currentLyricIndex != -1) {
        _currentLyricIndex = -1;
        if (_meizuLyricsEnabledSignal.value) {
          MeizuLyricsService.stopLyric();
        }
      }
      return;
    }
    final t = _position;
    int lo = 0, hi = timed.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final mt = timed[mid].time!;
      if (mt <= t) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final idxInAll = _lyricsLines.indexOf(timed[ans]);
    if (_currentLyricIndex != idxInAll) {
      _currentLyricIndex = idxInAll;
      if (_meizuLyricsEnabledSignal.value) {
        MeizuLyricsService.updateLyric(_lyricsLines[idxInAll].text);
      }
    }
  }

  void toggleShuffle() {
    _mode = _mode == PlaybackMode.shuffle ? PlaybackMode.loop : PlaybackMode.shuffle;
    _bump(playbackTick);
  }

  void toggleSingleLoop() {
    _mode = _mode == PlaybackMode.single ? PlaybackMode.loop : PlaybackMode.single;
    _bump(playbackTick);
  }

  void cyclePlaybackMode() {
    if (_mode == PlaybackMode.shuffle) {
      _mode = PlaybackMode.loop;
    } else if (_mode == PlaybackMode.loop) {
      _mode = PlaybackMode.single;
    } else {
      _mode = PlaybackMode.shuffle;
    }
    _bump(playbackTick);
    StorageUtil.setString(StorageKeys.playbackMode, _mode.name);
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepUntilSongEnd = false;
    _sleepUntil = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      pause();
      _sleepTimer = null;
      _sleepUntil = null;
      _sleepUntilSongEnd = false;
      _bump(sleepTick);
    });
    _bump(sleepTick);
  }

  void setSleepTimerToSongEnd() {
    final remaining = _duration - _position;
    if (remaining <= Duration.zero) {
      pause();
      cancelSleepTimer();
      return;
    }
    _sleepTimer?.cancel();
    _sleepUntilSongEnd = true;
    _sleepUntil = DateTime.now().add(remaining);
    _sleepTimer = Timer(remaining, () {
      pause();
      _sleepTimer = null;
      _sleepUntil = null;
      _sleepUntilSongEnd = false;
      _bump(sleepTick);
    });
    _bump(sleepTick);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepUntil = null;
    _sleepUntilSongEnd = false;
    _bump(sleepTick);
  }

  Future<Response> _fetchWithManualRedirect(Dio dio, Uri uri, Options options) async {
    dio.options.followRedirects = false;
    dio.options.validateStatus = (status) => true;

    var currentUri = uri;
    var currentOptions = options;
    if (currentOptions.headers != null) {
      currentOptions = currentOptions.copyWith(headers: Map<String, dynamic>.from(currentOptions.headers!));
    }

    for (var i = 0; i < 5; i++) {
       try {
         final response = await dio.getUri(
           currentUri,
           options: currentOptions,
         );
         
         if (response.statusCode != null && (response.statusCode! >= 300 && response.statusCode! < 400)) {
           final location = response.headers.value(HttpHeaders.locationHeader);
           if (location != null && location.isNotEmpty) {
             final newUri = currentUri.resolve(location);
             if (newUri.host != currentUri.host) {
               if (kDebugMode) {
                 debugPrint('WebDAV: Redirecting to different host, dropping auth headers');
               }
               currentOptions.headers?.remove(HttpHeaders.authorizationHeader);
               currentOptions.headers?.remove('Authorization');
             }
             currentUri = newUri;
             continue;
           }
         }
         return response;
       } catch (e) {
         if (i == 4) rethrow;
       }
    }
    throw Exception('Too many redirects');
  }

  Uri? _getSafeUri(String uriStr) {
    try {
      return Uri.parse(uriStr);
    } catch (_) {
      try {
        return Uri.parse(Uri.encodeFull(uriStr));
      } catch (_) {
        return null;
      }
    }
  }

}

class _ColorBucket {
  int count;
  int r;
  int g;
  int b;
  _ColorBucket(this.count, this.r, this.g, this.b);
}

enum PlaybackMode {
  shuffle,
  loop,
  single,
}
