import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../app.dart';
import '../core/cache/cache_manager.dart';
import '../core/database/database_helper.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../services/display_mode_service.dart';
import '../viewmodels/library_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/app_toast.dart';
import '../widgets/labeled_slider.dart';
import 'settings/gradient_settings_page.dart';
import 'settings/lyrics_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _enableSoftDecoding = false;

  @override
  void initState() {
    super.initState();
    _enableSoftDecoding = StorageUtil.getBoolOrDefault(
      StorageKeys.enableSoftDecoding,
      defaultValue: false,
    );
    if (_enableSoftDecoding) {
      _enableSoftDecoding = false;
      StorageUtil.setBool(StorageKeys.enableSoftDecoding, false);
    }
  }

  void _openAppearancePage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppearancePage()),
    );
  }

  void _openDatabaseSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DatabaseSettingsPage()),
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
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
              '用户界面',
              [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('外观'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openAppearancePage,
                ),
              ],
            ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '播放设置',
                    [
                      ListTile(
                        leading: const Icon(Icons.tune),
                        title: const Text('强制软件解码'),
                        subtitle: const Text('播放异常时尝试开启'),
                        onTap: () => AppToast.show(context, '暂时无效'),
                        trailing: Switch(
                          value: _enableSoftDecoding,
                          onChanged: (v) async {
                            AppToast.show(context, '暂时无效');
                            if (_enableSoftDecoding) {
                              setState(() {
                                _enableSoftDecoding = false;
                              });
                            }
                            await StorageUtil.setBool(StorageKeys.enableSoftDecoding, false);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '功能',
                    [
                      ListTile(
                        leading: const Icon(Icons.lyrics_outlined),
                        title: const Text('歌词设置'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                           Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const LyricsSettingsPage()),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.storage),
                        title: const Text('数据库设置'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openDatabaseSettingsPage,
                      ),
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
}

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Widget _modeTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? scheme.primary
        : (isDark ? Colors.white12 : Colors.black12);
    final iconColor =
        selected ? scheme.primary : (isDark ? Colors.white70 : Colors.black54);
    final textColor =
        selected ? scheme.primary : (isDark ? Colors.white70 : Colors.black87);
    final background =
        selected ? scheme.primary.withAlpha(31) : Colors.transparent;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRow(
    BuildContext context, {
    required ThemeMode selected,
    required ValueChanged<ThemeMode> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          _modeTile(
            context,
            icon: Icons.phone_android,
            label: _themeLabel(ThemeMode.system),
            selected: selected == ThemeMode.system,
            onTap: () => onChanged(ThemeMode.system),
          ),
          const SizedBox(width: 8),
          _modeTile(
            context,
            icon: Icons.light_mode_outlined,
            label: _themeLabel(ThemeMode.light),
            selected: selected == ThemeMode.light,
            onTap: () => onChanged(ThemeMode.light),
          ),
          const SizedBox(width: 8),
          _modeTile(
            context,
            icon: Icons.dark_mode_outlined,
            label: _themeLabel(ThemeMode.dark),
            selected: selected == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
          ),
        ],
      ),
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
        title: const Text('外观'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                    '应用界面',
                    [
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: App.themeModeNotifier,
                        builder: (context, mode, _) {
                          return _modeRow(
                            context,
                            selected: mode,
                            onChanged: App.setThemeMode,
                          );
                        },
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: App.dynamicColorNotifier,
                        builder: (context, enabled, _) {
                          return ListTile(
                            leading: const Icon(Icons.color_lens_outlined),
                            title: const Text('使用系统动态颜色'),
                            subtitle: const Text('仅 Android 12+ 生效'),
                            trailing: Switch(
                              value: enabled,
                              onChanged: (v) => App.setDynamicColorEnabled(v),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '显示',
                    [
                      ValueListenableBuilder<RefreshRateMode>(
                        valueListenable: DisplayModeService.modeNotifier,
                        builder: (context, mode, _) {
                          return ListTile(
                            leading: const Icon(Icons.speed),
                            title: const Text('屏幕刷新率'),
                            subtitle: Text(
                              switch (mode) {
                                RefreshRateMode.auto => '自动',
                                RefreshRateMode.high => '高刷新率',
                                RefreshRateMode.low => '低刷新率 (省电)',
                              },
                            ),
                            trailing: DropdownButton<RefreshRateMode>(
                              value: mode,
                              underline: const SizedBox(),
                              onChanged: (newMode) {
                                if (newMode != null) {
                                  DisplayModeService.setMode(newMode);
                                }
                              },
                              items: const [
                                DropdownMenuItem(
                                  value: RefreshRateMode.auto,
                                  child: Text('自动'),
                                ),
                                DropdownMenuItem(
                                  value: RefreshRateMode.high,
                                  child: Text('高刷'),
                                ),
                                DropdownMenuItem(
                                  value: RefreshRateMode.low,
                                  child: Text('低刷'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '播放界面',
                    [
                      Watch.builder(builder: (context) {
                        final vm = PlayerViewModel();
                        watchSignal(context, vm.uiTick);
                        return _modeRow(
                          context,
                          selected: vm.playbackThemeMode,
                          onChanged: vm.setPlaybackThemeMode,
                        );
                      },),
                      Watch.builder(builder: (context) {
                        final vm = PlayerViewModel();
                        watchSignal(context, vm.uiTick);
                        return Column(
                          children: [
                            SwitchListTile(
                              title: const Text('动态流光'),
                              subtitle: const Text('背景随封面颜色流动变化'),
                              value: vm.dynamicGradientEnabled,
                              onChanged: (v) => vm.setDynamicGradientEnabled(v),
                            ),
                            if (vm.dynamicGradientEnabled) ...[
                              const SizedBox(height: 6),
                              ListTile(
                                leading: const Icon(Icons.tune),
                                title: const Text('流光设置'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const GradientSettingsPage(),
                                    ),
                                  );
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
}

class DatabaseSettingsPage extends StatefulWidget {
  const DatabaseSettingsPage({super.key});

  @override
  State<DatabaseSettingsPage> createState() => _DatabaseSettingsPageState();
}

class _DatabaseSettingsPageState extends State<DatabaseSettingsPage> {
  int _limitMb = 1024;
  int _audioCacheSize = 0;
  int _coverCacheSize = 0;
  int _lyricsCacheSize = 0;
  bool _cacheLocalCover = false;
  int _artworkPrefetchConcurrency = 8;

  @override
  void initState() {
    super.initState();
    _limitMb = StorageUtil.getIntOrDefault(
      StorageKeys.cacheSizeLimitMb,
      defaultValue: 1024,
    );
    _cacheLocalCover = StorageUtil.getBoolOrDefault(
      StorageKeys.cacheLocalCover,
      defaultValue: false,
    );
    _artworkPrefetchConcurrency = StorageUtil.getIntOrDefault(
      StorageKeys.artworkPrefetchConcurrency,
      defaultValue: 8,
    );
    if (_artworkPrefetchConcurrency < 1) {
      _artworkPrefetchConcurrency = 1;
    }
    _refreshSizes();
  }

  Future<void> _refreshSizes() async {
    final cacheManager = CacheManager();
    final dbHelper = DatabaseHelper();
    final audioSize = await cacheManager.getAudioCacheSize();
    final coverSize = await cacheManager.getCoverCacheSize();
    final lyricsSize = await dbHelper.getLyricsCacheSize();
    if (!mounted) return;
    setState(() {
      _audioCacheSize = audioSize;
      _coverCacheSize = coverSize;
      _lyricsCacheSize = lyricsSize;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx++;
    }
    return '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[idx]}';
  }

  List<DropdownMenuItem<int>> _limitItems() {
    final options = <int>[256, 512, 1024, 2048, 5120, 0];
    return options.map((v) {
      final label = v == 0 ? '不限制' : '${v}MB';
      return DropdownMenuItem<int>(
        value: v,
        child: Text(label),
      );
    }).toList();
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

  @override
  Widget build(BuildContext context) {
    final total = _audioCacheSize + _coverCacheSize + _lyricsCacheSize;
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
        title: const Text('数据库设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: [
                  const Color(0x66FDE2A7),
                  const Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: [
                  const Color(0x66CBE8FF),
                  const Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _sectionCard(
                    context,
                    '常规设置',
                    [
                      ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: const Text('缓存本地封面'),
                        subtitle: const Text('提取本地音乐封面并缓存，加快加载速度但占用空间'),
                        trailing: Switch(
                          value: _cacheLocalCover,
                          onChanged: (v) async {
                            setState(() {
                              _cacheLocalCover = v;
                            });
                            await StorageUtil.setBool(StorageKeys.cacheLocalCover, v);
                            if (!mounted) return;
                            _refreshSizes();
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: LabeledSlider(
                          title: '封面并发',
                          value: _artworkPrefetchConcurrency.toDouble(),
                          min: 1,
                          max: 16,
                          divisions: 15,
                          label: '$_artworkPrefetchConcurrency',
                          valueText: '$_artworkPrefetchConcurrency',
                          description: '并发越高封面加载越快，但更耗资源',
                          onChanged: (v) {
                            setState(() {
                              _artworkPrefetchConcurrency = v.round();
                            });
                          },
                          onChangeEnd: (v) async {
                            final value = v.round() < 1 ? 1 : v.round();
                            await StorageUtil.setInt(
                              StorageKeys.artworkPrefetchConcurrency,
                              value,
                            );
                          },
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '缓存限制',
                    [
                      ListTile(
                        leading: const Icon(Icons.storage),
                        title: const Text('缓存大小限制'),
                        subtitle: const Text('限制音频缓存占用空间'),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _limitMb,
                            items: _limitItems(),
                            onChanged: (v) async {
                              if (v == null) return;
                              setState(() {
                                _limitMb = v;
                              });
                              await StorageUtil.setInt(
                                StorageKeys.cacheSizeLimitMb,
                                v,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    context,
                    '缓存详情',
                    [
                      ListTile(
                        leading: const Icon(Icons.music_note_outlined),
                        title: const Text('音频缓存'),
                        subtitle: Text(_formatBytes(_audioCacheSize)),
                        trailing: TextButton(
                          onPressed: () async {
                            await CacheManager().clearAudioCache();
                            await _refreshSizes();
                          },
                          child: const Text('清除'),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: const Text('封面缓存'),
                        subtitle: Text(_formatBytes(_coverCacheSize)),
                        trailing: TextButton(
                          onPressed: () async {
                            await CacheManager().clearCoverCache();
                            await _refreshSizes();
                          },
                          child: const Text('清除'),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.lyrics_outlined),
                        title: const Text('歌词缓存'),
                        subtitle: Text(_formatBytes(_lyricsCacheSize)),
                        trailing: TextButton(
                          onPressed: () async {
                            await LibraryViewModel().clearLyricsCache();
                            await _refreshSizes();
                          },
                          child: const Text('清除'),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('缓存总占用'),
                        subtitle: Text(_formatBytes(total)),
                        trailing: TextButton(
                          onPressed: () async {
                            await CacheManager().clearAllCache();
                            await LibraryViewModel().clearLyricsCache();
                            await _refreshSizes();
                          },
                          child: const Text('清除全部'),
                        ),
                      ),
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
}

class AppAppearancePage extends StatelessWidget {
  const AppAppearancePage({super.key});

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
        title: const Text('应用界面'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: [
                  const Color(0x66FDE2A7),
                  const Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: [
                  const Color(0x66CBE8FF),
                  const Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _sectionCard(
                    context,
                    '应用界面',
                    [
                      const ListTile(
                        leading: Icon(Icons.tune),
                        title: Text('暂无可配置项'),
                        subtitle: Text('后续界面细节设置会放在这里'),
                      ),
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
}
