import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/lyrics/lyrics_service.dart';
import '../../app/services/player/song_metadata_persister.dart';
import '../../components/index.dart';

class LyricsSettingsPage extends StatefulWidget {
  const LyricsSettingsPage({super.key});

  @override
  State<LyricsSettingsPage> createState() => _LyricsSettingsPageState();
}

class _LyricsSettingsPageState extends State<LyricsSettingsPage>
    with SignalsMixin {
  static const String _prefsMeizuLyrics = 'lyrics_meizu_enabled';
  static const String _prefsLyriconEnabled = 'lyrics_lyricon_enabled';
  static const String _prefsLyriconForceKaraoke =
      'lyrics_lyricon_force_karaoke';
  static const String _prefsLyriconHideTranslation =
      'lyrics_lyricon_hide_translation';

  late final _meizuLyrics = createSignal(false);
  late final _lyriconEnabled = createSignal(false);
  late final _lyriconForceKaraoke = createSignal(false);
  late final _lyriconHideTranslation = createSignal(false);
  late final _biliSubtitle = createSignal(true);
  late final _onlineLyrics = createSignal(true);
  late final _onlineTranslation = createSignal(true);
  late final _onlineCover = createSignal(true);
  late final _preferWordByWord = createSignal(true);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _meizuLyrics.value = prefs.getBool(_prefsMeizuLyrics) ?? false;
    _lyriconEnabled.value = prefs.getBool(_prefsLyriconEnabled) ?? false;
    _lyriconForceKaraoke.value =
        prefs.getBool(_prefsLyriconForceKaraoke) ?? false;
    _lyriconHideTranslation.value =
        prefs.getBool(_prefsLyriconHideTranslation) ?? false;
    _biliSubtitle.value =
        prefs.getBool(LyricsService.prefsBiliSubtitleEnabled) ?? true;
    _onlineLyrics.value =
        prefs.getBool(LyricsService.prefsOnlineLyricsEnabled) ?? true;
    _onlineTranslation.value =
        prefs.getBool(LyricsService.prefsOnlineLyricsTranslation) ?? true;
    _onlineCover.value =
        prefs.getBool(SongMetadataPersister.prefsOnlineCoverEnabled) ?? true;
    _preferWordByWord.value =
        prefs.getBool(LyricsService.prefsPreferWordByWord) ?? true;
    await LyricsService.instance.refreshSettings();
    _loading.value = false;
  }

  Future<void> _updateBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    await LyricsService.instance.refreshSettings();
  }

  void _setMeizuLyrics(bool value) async {
    _meizuLyrics.value = value;
    _updateBool(_prefsMeizuLyrics, value);
  }

  void _setLyriconEnabled(bool value) {
    _lyriconEnabled.value = value;
    _updateBool(_prefsLyriconEnabled, value);
  }

  void _setLyriconForceKaraoke(bool value) {
    _lyriconForceKaraoke.value = value;
    _updateBool(_prefsLyriconForceKaraoke, value);
  }

  void _setLyriconHideTranslation(bool value) {
    _lyriconHideTranslation.value = value;
    _updateBool(_prefsLyriconHideTranslation, value);
  }

  void _setBiliSubtitle(bool value) {
    _biliSubtitle.value = value;
    _updateBool(LyricsService.prefsBiliSubtitleEnabled, value);
    // 开关一变就重载当前歌曲：关掉之后不该继续显示刚拉来的字幕，
    // 打开之后也应该立刻去取一次。
    LyricsService.instance.reloadCurrentSong();
  }

  void _setOnlineLyrics(bool value) {
    _onlineLyrics.value = value;
    _updateBool(LyricsService.prefsOnlineLyricsEnabled, value);
    LyricsService.instance.reloadCurrentSong();
  }

  void _setOnlineTranslation(bool value) {
    _onlineTranslation.value = value;
    _updateBool(LyricsService.prefsOnlineLyricsTranslation, value);
  }

  void _setOnlineCover(bool value) {
    _onlineCover.value = value;
    _updateBool(SongMetadataPersister.prefsOnlineCoverEnabled, value);
  }

  void _setPreferWordByWord(bool value) {
    _preferWordByWord.value = value;
    _updateBool(LyricsService.prefsPreferWordByWord, value);
    // 逐字和整行是同一份歌词的两种呈现，切换后立刻按新的方式重建模型。
    LyricsService.instance.reloadCurrentSong();
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        if (_loading.value) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return AppPageScaffold(
          extendBodyBehindAppBar: true,
          appBar: const AppTopBar(
            title: '歌词设置',
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              AppSettingSection(
                title: '在线匹配',
                children: [
                  AppSettingSwitchTile(
                    title: '在线匹配歌词',
                    subtitle: '通过开发API获取歌词',
                    value: _onlineLyrics.value,
                    onChanged: _setOnlineLyrics,
                  ),
                  if (_onlineLyrics.value)
                    AppSettingSwitchTile(
                      title: '一并保存翻译',
                      subtitle: '接口有中文翻译时一起存下来',
                      value: _onlineTranslation.value,
                      onChanged: _setOnlineTranslation,
                    ),
                  AppSettingSwitchTile(
                    title: '在线匹配封面',
                    subtitle: '文件里没有内嵌封面时，按歌名找一张',
                    value: _onlineCover.value,
                    onChanged: _setOnlineCover,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSettingSection(
                title: '歌词来源',
                children: [
                  AppSettingSwitchTile(
                    title: 'B站字幕当歌词',
                    subtitle: '本地没有歌词时，自动取视频字幕（需登录 B 站账号）',
                    value: _biliSubtitle.value,
                    onChanged: _setBiliSubtitle,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSettingSection(
                title: '逐字歌词',
                children: [
                  AppSettingSwitchTile(
                    title: '优先使用逐字歌词',
                    subtitle: '在线匹配到逐字歌词时，用真实的每字时间做高亮，而不是按整行时长估算',
                    value: _preferWordByWord.value,
                    onChanged: _setPreferWordByWord,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSettingSection(
                title: '状态栏歌词',
                children: [
                  AppSettingSwitchTile(
                    title: '魅族状态栏歌词',
                    subtitle: '需要系统或插件支持，不然请勿开启',
                    value: _meizuLyrics.value,
                    onChanged: _setMeizuLyrics,
                  ),
                  AppSettingSwitchTile(
                    title: 'Lyricon 服务',
                    subtitle: '为状态栏歌词应用提供服务支持',
                    value: _lyriconEnabled.value,
                    onChanged: _setLyriconEnabled,
                  ),
                  if (_lyriconEnabled.value)
                    AppSettingSwitchTile(
                      title: '强制逐字',
                      subtitle: '使用软件逐字模拟，一般不用开启',
                      value: _lyriconForceKaraoke.value,
                      onChanged: _setLyriconForceKaraoke,
                    ),
                  if (_lyriconEnabled.value)
                    AppSettingSwitchTile(
                      title: '隐藏歌词翻译',
                      subtitle: '仅发送原文歌词',
                      value: _lyriconHideTranslation.value,
                      onChanged: _setLyriconHideTranslation,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
