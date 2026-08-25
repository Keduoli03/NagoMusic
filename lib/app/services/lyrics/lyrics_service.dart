import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as fl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

import '../player_service.dart';
import '../../state/song_state.dart';
import '../bili/bili_music_service.dart';
import '../log/log.dart';
import 'lyrics_parser.dart';
import 'lyrics_repository.dart';
import 'lyricon_service.dart';
import 'meizu_lyrics_service.dart';

enum LyricsLoadStatus { idle, loading, loaded, empty, failed }

class LyricsSnapshot {
  final LyricsLoadStatus status;
  final SongEntity? song;
  final fl.LyricModel? model;
  final Object? error;

  const LyricsSnapshot({
    required this.status,
    required this.song,
    required this.model,
    required this.error,
  });

  factory LyricsSnapshot.idle() {
    return const LyricsSnapshot(
      status: LyricsLoadStatus.idle,
      song: null,
      model: null,
      error: null,
    );
  }

  LyricsSnapshot copyWith({
    LyricsLoadStatus? status,
    SongEntity? song,
    Object? error,
    fl.LyricModel? model,
  }) {
    return LyricsSnapshot(
      status: status ?? this.status,
      song: song ?? this.song,
      model: model ?? this.model,
      error: error,
    );
  }
}

class LyricsService {
  static final LyricsService instance = LyricsService._internal();

  static const String _logTag = 'LyricsService';

  static const String _prefsLyriconEnabled = 'lyrics_lyricon_enabled';
  static const String _prefsLyriconForceKaraoke =
      'lyrics_lyricon_force_karaoke';
  static const String _prefsLyriconHideTranslation =
      'lyrics_lyricon_hide_translation';
  static const String _prefsMeizuLyrics = 'lyrics_meizu_enabled';
  static const String _prefsViewForceKaraoke = 'lyrics_view_force_karaoke';
  static const String prefsBiliSubtitleEnabled = 'lyrics_bili_subtitle_enabled';

  final LyricsRepository _repo = LyricsRepository();
  final PlayerService _player = PlayerService.instance;
  final LyricController controller = LyricController();
  final ValueNotifier<LyricsSnapshot> snapshot = ValueNotifier(
    LyricsSnapshot.idle(),
  );
  final ValueNotifier<String?> currentLineText = ValueNotifier(null);
  final ValueNotifier<int> viewSettingsTick = ValueNotifier(0);
  late final snapshotSignal = signal(LyricsSnapshot.idle());
  late final viewSettingsTickSignal = signal(0);
  late final activeIndexSignal = signal(controller.activeIndexNotifiter.value);
  late final lyricModelSignal = signal(controller.lyricNotifier.value);
  late final isSelectingSignal = signal(controller.isSelectingNotifier.value);
  late final selectedIndexSignal = signal(
    controller.selectedIndexNotifier.value,
  );

  int _loadSeq = 0;
  Timer? _lyriconPosTimer;
  int _lastLyriconPositionMs = -1;
  bool _lyriconEnabled = false;
  bool _lyriconForceKaraoke = false;
  bool _lyriconHideTranslation = false;
  bool _meizuEnabled = false;
  int _meizuLastIndex = -1;
  bool _viewForceKaraoke = false;
  bool _biliSubtitleEnabled = true;

  LyricsService._internal() {
    snapshot.addListener(() => snapshotSignal.value = snapshot.value);
    viewSettingsTick.addListener(
      () => viewSettingsTickSignal.value = viewSettingsTick.value,
    );
    controller.activeIndexNotifiter.addListener(
      () => activeIndexSignal.value = controller.activeIndexNotifiter.value,
    );
    controller.activeIndexNotifiter.addListener(_onActiveIndexChanged);
    controller.lyricNotifier.addListener(
      () => lyricModelSignal.value = controller.lyricNotifier.value,
    );
    controller.isSelectingNotifier.addListener(
      () => isSelectingSignal.value = controller.isSelectingNotifier.value,
    );
    controller.selectedIndexNotifier.addListener(
      () => selectedIndexSignal.value = controller.selectedIndexNotifier.value,
    );
    controller.setOnTapLineCallback((pos) {
      controller.stopSelection();
      _player.seek(pos);
    });
    _player.currentSong.addListener(_onSongChanged);
    _player.position.addListener(_onPositionChanged);
    _player.isPlaying.addListener(_onPlayingChanged);
    refreshSettings();
    _onSongChanged();
  }

  void notifyViewSettingsChanged() {
    viewSettingsTick.value = viewSettingsTick.value + 1;
  }

  Future<void> refreshSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _lyriconEnabled = prefs.getBool(_prefsLyriconEnabled) ?? false;
    _lyriconForceKaraoke = prefs.getBool(_prefsLyriconForceKaraoke) ?? false;
    _lyriconHideTranslation =
        prefs.getBool(_prefsLyriconHideTranslation) ?? false;
    _meizuEnabled = prefs.getBool(_prefsMeizuLyrics) ?? false;
    _viewForceKaraoke = prefs.getBool(_prefsViewForceKaraoke) ?? false;
    _biliSubtitleEnabled = prefs.getBool(prefsBiliSubtitleEnabled) ?? true;
    await LyriconService.setServiceEnabled(_lyriconEnabled);
    if (!_lyriconEnabled) {
      _lyriconPosTimer?.cancel();
      _lyriconPosTimer = null;
    } else {
      final song = _player.currentSong.value;
      await _syncLyriconSong(song, snapshot.value.model);
    }
    if (!_meizuEnabled) {
      _meizuLastIndex = -1;
      await MeizuLyricsService.stopLyric();
    } else {
      _updateMeizuLyricForIndex(controller.activeIndexNotifiter.value);
    }
  }

  void _onSongChanged() {
    final song = _player.currentSong.value;
    _loadForSong(song);
  }

  void _onPositionChanged() {
    final pos = _player.position.value;
    controller.setProgress(pos);
    _scheduleLyriconPosition(pos);
  }

  void _onPlayingChanged() {
    _syncLyriconPlaybackState();
  }

  void _onActiveIndexChanged() {
    _updateCurrentLineText(controller.activeIndexNotifiter.value);
    _updateMeizuLyricForIndex(controller.activeIndexNotifiter.value);
  }

  void reloadCurrentSong() {
    _loadForSong(_player.currentSong.value);
  }

  /// 取 B 站视频字幕当歌词，成功后写进歌词缓存，下次直接命中本地不再联网。
  ///
  /// 用 `overwrite: false` 保存：这条只是「本地什么都没有」时的兜底，
  /// 不该盖掉用户自己刮削或放进去的歌词。
  Future<String?> _loadBiliSubtitle(SongEntity song) async {
    try {
      final lrc = await BiliSubtitleService.instance.fetchLrc(song.id);
      if (lrc == null || lrc.trim().isEmpty) return null;
      await _repo.saveLrcToCache(song.id, lrc);
      return lrc;
    } catch (e, s) {
      // 没登录 / 该视频没字幕 / 网络不通 —— 都只是「这首没歌词」，不该弹错误，
      // 但仍然值得落盘一条 w，方便排查为什么某首歌一直没歌词。
      AppLog.instance.w(_logTag, 'B 站字幕获取失败 song=${song.title}', e, s);
      return null;
    }
  }

  Future<void> _loadForSong(SongEntity? song) async {
    final seq = ++_loadSeq;
    snapshot.value = snapshot.value.copyWith(
      status: LyricsLoadStatus.loading,
      song: song,
      model: null,
      error: null,
    );
    controller.lyricNotifier.value = null;
    currentLineText.value = null;

    if (song == null) {
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.empty,
        song: null,
        model: null,
        error: null,
      );
      await _syncLyriconSong(null, null);
      if (_meizuEnabled) {
        _meizuLastIndex = -1;
        await MeizuLyricsService.stopLyric();
      }
      return;
    }

    try {
      await refreshSettings();
      var lrc = await _repo.loadLrc(song);
      if (seq != _loadSeq) return;

      // 本地（内嵌标签 / 缓存 / 同名 .lrc）都没有时，B 站曲目再去取一次视频字幕。
      // 放在这里而不是 LyricsRepository 里，是为了让仓库保持「只读本地」的语义，
      // 联网获取属于编排层的事。
      if ((lrc == null || lrc.trim().isEmpty) &&
          _biliSubtitleEnabled &&
          BiliMusicService.isBiliSong(song)) {
        lrc = await _loadBiliSubtitle(song);
        if (seq != _loadSeq) return;
      }

      if (lrc == null || lrc.trim().isEmpty) {
        snapshot.value = snapshot.value.copyWith(
          status: LyricsLoadStatus.empty,
          song: song,
          model: null,
          error: null,
        );
        await _syncLyriconSong(song, null);
        if (_meizuEnabled) {
          _meizuLastIndex = -1;
          await MeizuLyricsService.stopLyric();
        }
        return;
      }

      final model = LyricsParser.buildModelFromRaw(
        lrc,
        songDuration: (song.durationMs == null)
            ? null
            : Duration(milliseconds: song.durationMs!),
        predictDuration: false,
        forceKaraoke: _viewForceKaraoke || _lyriconForceKaraoke,
      );
      if (kDebugMode) {
        final translationCount = model.lines
            .where((line) => (line.translation ?? '').trim().isNotEmpty)
            .length;
        debugPrint(
          '[Lyrics] parsed ${model.lines.length} lines, '
          '$translationCount translations for ${song.title}',
        );
      }
      controller.loadLyricModel(model);
      _updateCurrentLineText(controller.activeIndexNotifiter.value);
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.loaded,
        song: song,
        model: model,
        error: null,
      );
      await _syncLyriconSong(song, model);
      _updateMeizuLyricForIndex(controller.activeIndexNotifiter.value);
    } catch (e, s) {
      AppLog.instance.e(_logTag, '加载歌词失败 song=${song.title}', e, s);
      if (seq != _loadSeq) return;
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.failed,
        song: song,
        model: null,
        error: e,
      );
      await _syncLyriconSong(song, null);
      if (_meizuEnabled) {
        _meizuLastIndex = -1;
        await MeizuLyricsService.stopLyric();
      }
    }
  }

  void _updateCurrentLineText(int index) {
    final model = controller.lyricNotifier.value;
    if (model == null || model.lines.isEmpty) {
      currentLineText.value = null;
      return;
    }
    if (index < 0 || index >= model.lines.length) {
      currentLineText.value = null;
      return;
    }
    final text = model.lines[index].text.trim();
    currentLineText.value = text.isEmpty ? null : text;
  }

  Future<void> _syncLyriconPlaybackState() async {
    if (!_lyriconEnabled) return;
    await LyriconService.setPlaybackState(_player.isPlaying.value);
  }

  void _scheduleLyriconPosition(Duration position) {
    if (!_lyriconEnabled) return;
    _lyriconPosTimer ??= Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) async {
      await _flushLyriconPosition();
    });
  }

  Future<void> _flushLyriconPosition() async {
    if (!_lyriconEnabled) return;
    final ms = _player.position.value.inMilliseconds;
    if ((ms - _lastLyriconPositionMs).abs() < 150) return;
    _lastLyriconPositionMs = ms;
    await LyriconService.updatePosition(ms);
  }

  Future<void> _syncLyriconSong(SongEntity? song, fl.LyricModel? model) async {
    await LyriconService.setServiceEnabled(_lyriconEnabled);
    if (!_lyriconEnabled) return;
    if (song == null) return;
    await LyriconService.setSong(
      song,
      model,
      hideTranslation: _lyriconHideTranslation,
    );
    await LyriconService.setDisplayTranslation(!_lyriconHideTranslation);
    await LyriconService.setPlaybackState(_player.isPlaying.value);
  }

  void _updateMeizuLyricForIndex(int index) {
    if (!_meizuEnabled) return;
    final model = controller.lyricNotifier.value;
    if (model == null) {
      if (_meizuLastIndex != -1) {
        _meizuLastIndex = -1;
        MeizuLyricsService.stopLyric();
      }
      return;
    }
    if (index < 0 || index >= model.lines.length) {
      if (_meizuLastIndex != -1) {
        _meizuLastIndex = -1;
        MeizuLyricsService.stopLyric();
      }
      return;
    }
    if (_meizuLastIndex == index) return;
    _meizuLastIndex = index;
    final text = model.lines[index].text.trim();
    if (text.isEmpty) {
      MeizuLyricsService.stopLyric();
      return;
    }
    MeizuLyricsService.updateLyric(text);
  }
}
