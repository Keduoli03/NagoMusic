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
import '../online_meta/online_metadata_service.dart';
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

  /// 本地没有歌词时，自动去 QQ 音乐按歌名匹配一份。默认开。
  static const String prefsOnlineLyricsEnabled = 'lyrics_online_enabled';

  /// 匹配到的歌词是否连翻译一起存。默认开。
  static const String prefsOnlineLyricsTranslation =
      'lyrics_online_translation';

  /// 有逐字歌词（yrc）时优先用它做卡拉OK高亮。默认开。
  static const String prefsPreferWordByWord = 'lyrics_prefer_word_by_word';

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

  /// 当前已加载（或正在加载）的歌曲 id，用来挡掉同一首歌的重复触发。
  String? _loadedSongId;

  /// 正在自己写歌词的那首歌。  ///
  /// `_loadForSong` 里的在线匹配写完歌词会触发 [LyricsRepository.changes]，
  /// 不排掉的话会让刚跑到一半的这次加载再被强制重跑一遍。
  String? _selfWritingSongId;

  void _onLyricsCacheChanged(String songId) {
    if (songId == _selfWritingSongId) return;
    final current = _player.currentSong.value;
    if (current == null || current.id != songId) return;
    _loadForSong(current, force: true);
  }

  Timer? _lyriconPosTimer;
  int _lastLyriconPositionMs = -1;
  bool _lyriconEnabled = false;
  bool _lyriconForceKaraoke = false;
  bool _lyriconHideTranslation = false;
  bool _meizuEnabled = false;
  int _meizuLastIndex = -1;
  bool _viewForceKaraoke = false;
  bool _biliSubtitleEnabled = true;
  bool _onlineLyricsEnabled = true;
  bool _onlineLyricsTranslation = true;
  bool _preferWordByWord = true;

  /// 这一轮已经联网找过、但没找到歌词的歌曲。
  ///
  /// 没有这个集合的话，每次切回一首没歌词的歌都会重新发一轮搜索 + 取词请求 ——
  /// 单曲循环一首没歌词的歌就是无限重试。只在进程内有效，重启后会再试一次。
  final Set<String> _onlineLyricsMisses = <String>{};

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
    // 歌词缓存真的变了才重载（内嵌标签刮削稍后写入、在线匹配、手动清除）。
    // 上面那个 currentSong 监听只负责「换歌」，换实例不算。
    //
    // 不持有订阅：LyricsService 是全局单例，活到进程结束，没有需要退订的时机。
    LyricsRepository.changes.listen(_onLyricsCacheChanged);
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
    _onlineLyricsEnabled = prefs.getBool(prefsOnlineLyricsEnabled) ?? true;
    _onlineLyricsTranslation =
        prefs.getBool(prefsOnlineLyricsTranslation) ?? true;
    _preferWordByWord = prefs.getBool(prefsPreferWordByWord) ?? true;
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
    // 手动重载是明确的「再试一次」意图，清掉这首的失败记录，否则上一轮联网没
    // 找到之后，用户在面板里手动匹配完再回来仍然会被挡在缓存外面。
    final song = _player.currentSong.value;
    if (song != null) _onlineLyricsMisses.remove(song.id);
    _loadForSong(song, force: true);
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

  /// 本地和 B 站都没有时，按歌名去 QQ 音乐匹配一份歌词。
  ///
  /// 只取歌词 —— 标题/歌手/封面不动。每播一首就顺手改一次库的风险远大于收益，
  /// 要改那些请从「在线匹配」面板明确选（见 `OnlineMetadataService.apply`）。
  Future<String?> _loadOnlineLyrics(SongEntity song) async {
    if (_onlineLyricsMisses.contains(song.id)) return null;
    _selfWritingSongId = song.id;
    try {
      final found = await OnlineMetadataService.instance.fetchLyricsOnly(
        song: song,
        includeTranslation: _onlineLyricsTranslation,
      );
      if (!found) {
        _onlineLyricsMisses.add(song.id);
        return null;
      }
      return _repo.loadCachedLrc(song.id);
    } catch (e, s) {
      // 网络不通 / 接口挂了 —— 和「这首没歌词」在界面上是同一个结果，不该弹错误。
      AppLog.instance.w(_logTag, '在线歌词匹配失败 song=${song.title}', e, s);
      _onlineLyricsMisses.add(song.id);
      return null;
    } finally {
      _selfWritingSongId = null;
    }
  }

  Future<void> _loadForSong(SongEntity? song, {bool force = false}) async {
    // 同一首歌的重复触发一律忽略，不管当前是 loaded 还是 empty。
    //
    // 播放器每次回写元数据（补封面 / 时长 / 标签）都会把 currentSong 换成一个
    // **新的** SongEntity 实例，而下面第一件事就是把界面清成 loading 再重建 ——
    // 有歌词时表现为歌词闪一下，没歌词时表现为「暂无歌词」反复闪。
    //
    // 「歌词稍后才到货」的情况不靠这里重试，改由 LyricsRepository.changes 通知
    // （见构造函数里的订阅）—— 那才是歌词真的变了的信号，而 currentSong 换实例
    // 不是。
    if (!force && song != null && song.id == _loadedSongId) {
      return;
    }
    _loadedSongId = song?.id;

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

      // 还是没有就去 QQ 音乐按歌名匹配。放在最后：本地的、内嵌的、B 站字幕的
      // 都比网上猜来的更可能是对的。
      if ((lrc == null || lrc.trim().isEmpty) && _onlineLyricsEnabled) {
        lrc = await _loadOnlineLyrics(song);
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

      final songDuration = (song.durationMs == null)
          ? null
          : Duration(milliseconds: song.durationMs!);

      // 有逐字歌词就优先用它：yrc 带的是真实的每字时间，而普通 LRC 只能靠整行
      // 时长把字均摊出来。翻译仍然从上面那份 lrc 里取（yrc 不带翻译）。
      fl.LyricModel? model;
      if (_preferWordByWord) {
        final yrc = await _repo.loadYrc(song.id);
        if (seq != _loadSeq) return;
        if (yrc != null && yrc.trim().isNotEmpty) {
          model = LyricsParser.buildModelFromYrc(
            yrc,
            translationSource: lrc,
            songDuration: songDuration,
          );
        }
      }

      model ??= LyricsParser.buildModelFromRaw(
        lrc,
        songDuration: songDuration,
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
