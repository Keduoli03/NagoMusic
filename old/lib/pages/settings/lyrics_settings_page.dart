import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../core/storage/storage_keys.dart';
import '../../core/storage/storage_util.dart';
import '../../viewmodels/player_viewmodel.dart';

class LyricsSettingsPage extends StatefulWidget {
  const LyricsSettingsPage({super.key});

  @override
  State<LyricsSettingsPage> createState() => _LyricsSettingsPageState();
}

class _LyricsSettingsPageState extends State<LyricsSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1C1F24),
              Color(0xFF22262C),
              Color(0xFF1B1D22),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF6F7FB),
              Color(0xFFF7F3E8),
              Color(0xFFF1F7F4),
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('歌词设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: const [
                  Color(0x66FDE2A7),
                  Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: const [
                  Color(0x66CBE8FF),
                  Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _sectionCard(
                    context,
                    '状态栏歌词',
                    [
                   Watch.builder(builder: (context) {
                        final vm = PlayerViewModel();
                        watchSignal(context, vm.lyricsTick);
                        final enabled = vm.lyriconEnabled;
                        return Column(
                          children: [
                            SwitchListTile(
                              title: const Text('魅族状态栏歌词'),
                              subtitle: const Text('需要系统或插件支持，不然请勿开启'),
                              value: vm.meizuLyricsEnabled,
                              onChanged: (v) {
                                vm.setMeizuLyricsEnabled(v);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Lyricon 服务'),
                              subtitle: const Text('为状态栏歌词应用提供服务支持'),
                              value: enabled,
                              onChanged: (v) {
                                vm.setLyriconEnabled(v);
                                StorageUtil.setBool(StorageKeys.lyriconEnabled, v);
                              },
                            ),
                            if (enabled) ...[
                              SwitchListTile(
                                title: const Text('强制逐字'),
                                subtitle: const Text('使用软件的逐字模拟，一般不用开启'),
                                value: vm.lyriconForceKaraoke,
                                onChanged: (v) {
                                  vm.setLyriconForceKaraoke(v);
                                  StorageUtil.setBool(StorageKeys.lyriconForceKaraoke, v);
                                },
                              ),
                              SwitchListTile(
                                title: const Text('隐藏歌词翻译'),
                                subtitle: const Text('仅发送原文歌词'),
                                value: vm.lyriconHideTranslation,
                                onChanged: (v) {
                                  vm.setLyriconHideTranslation(v);
                                  StorageUtil.setBool(StorageKeys.lyriconHideTranslation, v);
                                },
                              ),
                            ],
                          ],
                        );
                      },),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow({
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white70 : Colors.black87;
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark
        ? const Color.fromARGB(28, 0, 0, 0)
        : const Color.fromARGB(15, 0, 0, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(children: _withDividers(items)),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.isEmpty) return items;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(items[i]);
      if (i != items.length - 1) {
        children.add(const SizedBox(height: 6));
      }
    }
    return children;
  }
}
