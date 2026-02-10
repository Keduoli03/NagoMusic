import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services/lyrics/lyrics_service.dart';
import '../../components/index.dart';

class LyricsSettingsPage extends StatefulWidget {
  const LyricsSettingsPage({super.key});

  @override
  State<LyricsSettingsPage> createState() => _LyricsSettingsPageState();
}

class _LyricsSettingsPageState extends State<LyricsSettingsPage> {
  static const String _prefsMeizuLyrics = 'lyrics_meizu_enabled';
  static const String _prefsLyriconEnabled = 'lyrics_lyricon_enabled';
  static const String _prefsLyriconForceKaraoke = 'lyrics_lyricon_force_karaoke';
  static const String _prefsLyriconHideTranslation =
      'lyrics_lyricon_hide_translation';

  bool _meizuLyrics = false;
  bool _lyriconEnabled = false;
  bool _lyriconForceKaraoke = false;
  bool _lyriconHideTranslation = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _meizuLyrics = prefs.getBool(_prefsMeizuLyrics) ?? false;
      _lyriconEnabled = prefs.getBool(_prefsLyriconEnabled) ?? false;
      _lyriconForceKaraoke = prefs.getBool(_prefsLyriconForceKaraoke) ?? false;
      _lyriconHideTranslation =
          prefs.getBool(_prefsLyriconHideTranslation) ?? false;
      _loading = false;
    });
  }

  Future<void> _updateBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    await LyricsService.instance.refreshSettings();
  }

  void _setMeizuLyrics(bool value) {
    setState(() => _meizuLyrics = value);
    _updateBool(_prefsMeizuLyrics, value);
  }

  void _setLyriconEnabled(bool value) {
    setState(() => _lyriconEnabled = value);
    _updateBool(_prefsLyriconEnabled, value);
  }

  void _setLyriconForceKaraoke(bool value) {
    setState(() => _lyriconForceKaraoke = value);
    _updateBool(_prefsLyriconForceKaraoke, value);
  }

  void _setLyriconHideTranslation(bool value) {
    setState(() => _lyriconHideTranslation = value);
    _updateBool(_prefsLyriconHideTranslation, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
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
            title: '状态栏歌词',
            children: [
              AppSettingSwitchTile(
                title: '魅族状态栏歌词',
                subtitle: '需要系统或插件支持，不然请勿开启',
                value: _meizuLyrics,
                onChanged: _setMeizuLyrics,
              ),
              AppSettingSwitchTile(
                title: 'Lyricon 服务',
                subtitle: '为状态栏歌词应用提供服务支持',
                value: _lyriconEnabled,
                onChanged: _setLyriconEnabled,
              ),
              if (_lyriconEnabled)
                AppSettingSwitchTile(
                  title: '强制逐字',
                  subtitle: '使用软件逐字模拟，一般不用开启',
                  value: _lyriconForceKaraoke,
                  onChanged: _setLyriconForceKaraoke,
                ),
              if (_lyriconEnabled)
                AppSettingSwitchTile(
                  title: '隐藏歌词翻译',
                  subtitle: '仅发送原文歌词',
                  value: _lyriconHideTranslation,
                  onChanged: _setLyriconHideTranslation,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
