import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;
import '../../app/services/cache/audio_cache_service.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';
import '../../app/utils/format_utils.dart';

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage>
    with SignalsMixin {
  late final _audioCacheSize = createSignal(0);
  late final _artworkCacheSize = createSignal(0);
  late final _lyricsCacheSize = createSignal(0);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    AppCacheSettings.ensureLoaded();
    SongDownloadSettings.ensureLoaded();
    LibraryRefreshSettings.ensureLoaded();
    WebDavPlaybackSettings.ensureLoaded();
    _loadCacheSizes();
  }

  Future<void> _pickDownloadDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return;
    await SongDownloadSettings.setCustomDirectoryPath(path);
    await SongDownloadSettings.setUseCustomDirectory(true);
    if (!mounted) return;
    AppToast.show(context, '已设置下载目录');
  }

  Future<void> _clearDownloadDirectory() async {
    await SongDownloadSettings.setUseCustomDirectory(false);
    await SongDownloadSettings.setCustomDirectoryPath(null);
    if (!mounted) return;
    AppToast.show(context, '已恢复为系统下载目录');
  }

  Future<void> _loadCacheSizes() async {
    _loading.value = true;
    final audioSize = await AudioCacheService.instance.getCacheSize();
    final artworkSize = await _getArtworkCacheSize();
    final lyricsSize = await _getLyricsCacheSize();
    if (!mounted) return;
    _audioCacheSize.value = audioSize;
    _artworkCacheSize.value = artworkSize;
    _lyricsCacheSize.value = lyricsSize;
    _loading.value = false;
  }

  Future<int> _getArtworkCacheSize() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
    return _dirSize(cacheDir);
  }

  Future<int> _getLyricsCacheSize() async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(dir.path, 'lyrics'));
    return _dirSize(cacheDir);
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          total += await f.length();
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _clearAudioCache() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除音频缓存',
      content: '确定要清除音频缓存吗？这将需要重新下载音频文件。',
    );
    if (confirmed != true) return;

    _loading.value = true;
    await AudioCacheService.instance.clearCache();
    if (!mounted) return;
    await _loadCacheSizes();
    if (!mounted) return;
    AppToast.show(context, '音频缓存已清除');
  }

  Future<void> _clearArtworkCache() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除封面缓存',
      content: '确定要清除封面缓存吗？这将需要重新生成封面缩略图。',
    );
    if (confirmed != true) return;

    _loading.value = true;
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'artwork_cache'));
    if (await cacheDir.exists()) {
      try {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
      } catch (_) {}
    }
    if (!mounted) return;
    await _loadCacheSizes();
    if (!mounted) return;
    AppToast.show(context, '封面缓存已清除');
  }

  Future<void> _clearLyricsCache() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除歌词缓存',
      content: '确定要清除歌词缓存吗？本地歌词会在需要时重新读取。',
    );
    if (confirmed != true) return;

    _loading.value = true;
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(dir.path, 'lyrics'));
    if (await cacheDir.exists()) {
      try {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
      } catch (_) {}
    }
    if (!mounted) return;
    await _loadCacheSizes();
    if (!mounted) return;
    AppToast.show(context, '歌词缓存已清除');
  }

  Future<void> _clearAllCaches() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除缓存',
      content: '确定要清除音频、封面和歌词缓存吗？',
    );
    if (confirmed != true) return;

    _loading.value = true;
    await AudioCacheService.instance.clearCache();
    if (!mounted) return;
    final docDir = await getApplicationDocumentsDirectory();
    final artworkDir = Directory(p.join(docDir.path, 'artwork_cache'));
    if (await artworkDir.exists()) {
      try {
        await artworkDir.delete(recursive: true);
        await artworkDir.create(recursive: true);
      } catch (_) {}
    }
    final supportDir = await getApplicationSupportDirectory();
    final lyricsDir = Directory(p.join(supportDir.path, 'lyrics'));
    if (await lyricsDir.exists()) {
      try {
        await lyricsDir.delete(recursive: true);
        await lyricsDir.create(recursive: true);
      } catch (_) {}
    }

    await _loadCacheSizes();
    if (!mounted) return;
    AppToast.show(context, '缓存已清除');
  }

  String _limitLabel(int gb) {
    if (gb <= 0) return '无限制';
    return '$gb GB';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '存储与缓存',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Watch.builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          children: [
            AppSettingSection(
              title: '缓存管理',
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: AppCacheSettings.audioCacheLimitGb,
                  builder: (context, gb, _) {
                    final sliderValue = gb <= 0 ? 6.0 : gb.toDouble();
                    return AppSettingSlider(
                      title: '缓存上限',
                      description: '达到上限后会自动清理旧缓存',
                      value: sliderValue,
                      min: 1,
                      max: 6,
                      divisions: 5,
                      valueText: _limitLabel(gb),
                      onChanged: (value) {
                        final v = value.round();
                        AppCacheSettings.setAudioCacheLimitGb(v >= 6 ? 0 : v);
                      },
                    );
                  },
                ),
                AppSettingTile(
                  title: '音频缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${formatFileSize(_audioCacheSize.value, fractionDigits: 2, placeholder: '0 B')}',
                  trailing: Icon(Icons.music_note_outlined),
                  onTap: _loading.value ? null : _clearAudioCache,
                ),
                AppSettingTile(
                  title: '封面缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${formatFileSize(_artworkCacheSize.value, fractionDigits: 2, placeholder: '0 B')}',
                  trailing: const Icon(Icons.image_outlined),
                  onTap: _loading.value ? null : _clearArtworkCache,
                ),
                AppSettingTile(
                  title: '歌词缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${formatFileSize(_lyricsCacheSize.value, fractionDigits: 2, placeholder: '0 B')}',
                  trailing: const Icon(Icons.description_outlined),
                  onTap: _loading.value ? null : _clearLyricsCache,
                ),
                AppSettingTile(
                  title: '清空全部缓存',
                  subtitle: '清除音频、封面与歌词缓存',
                  trailing: const Icon(Icons.delete_forever_outlined),
                  onTap: _loading.value ? null : _clearAllCaches,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppSettingSection(
              title: '云端播放',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.prefetchEnabled,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '预取下一首',
                      subtitle: '提前缓存下一首减少卡顿',
                      value: enabled,
                      onChanged: WebDavPlaybackSettings.setPrefetchEnabled,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '分段并发下载',
                      subtitle: '提高弱网下缓存速度',
                      value: enabled,
                      onChanged: WebDavPlaybackSettings.setSegmentedEnabled,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                  builder: (context, enabled, _) {
                    if (!enabled) return const SizedBox.shrink();
                    return ValueListenableBuilder<int>(
                      valueListenable:
                          WebDavPlaybackSettings.segmentConcurrency,
                      builder: (context, count, _) {
                        return AppSettingSlider(
                          title: '分段并发数',
                          description: '并发越高速度越快但更耗网络',
                          value: count.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          valueText: '$count',
                          onChanged: (value) {
                            WebDavPlaybackSettings.setSegmentConcurrency(
                              value.round(),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppSettingSection(
              title: '下载设置',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: SongDownloadSettings.useCustomDirectory,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '使用自定义下载目录',
                      subtitle: enabled
                          ? '保存到你设置的文件夹'
                          : '默认保存到 Download/NagoMusic',
                      value: enabled,
                      onChanged: (value) async {
                        if (value &&
                            (SongDownloadSettings.customDirectoryPath.value ??
                                    '')
                                .trim()
                                .isEmpty) {
                          await _pickDownloadDirectory();
                          return;
                        }
                        await SongDownloadSettings.setUseCustomDirectory(value);
                      },
                    );
                  },
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: SongDownloadSettings.customDirectoryPath,
                  builder: (context, pathValue, _) {
                    final subtitle =
                        (pathValue == null || pathValue.trim().isEmpty)
                        ? '未设置，当前使用 Download/NagoMusic'
                        : pathValue;
                    return AppSettingNavTile(
                      title: '下载路径',
                      subtitle: subtitle,
                      onTap: _pickDownloadDirectory,
                    );
                  },
                ),
                AppSettingTile(
                  title: '恢复默认下载路径',
                  subtitle: '切回系统 Download/NagoMusic 目录',
                  trailing: const Icon(Icons.refresh_rounded),
                  onTap: _clearDownloadDirectory,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppSettingSection(
              title: '启动刷新',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable:
                      LibraryRefreshSettings.autoRefreshLocalOnLaunch,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '启动时刷新本地音源',
                      subtitle: '进入应用后自动检查本地是否有新增歌曲',
                      value: enabled,
                      onChanged: (value) {
                        LibraryRefreshSettings.setAutoRefreshLocalOnLaunch(
                          value,
                        );
                      },
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable:
                      LibraryRefreshSettings.autoRefreshCloudOnLaunch,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '启动时刷新云端音源',
                      subtitle: '进入应用后自动检查 WebDAV 是否有新增歌曲',
                      value: enabled,
                      onChanged: (value) {
                        LibraryRefreshSettings.setAutoRefreshCloudOnLaunch(
                          value,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
