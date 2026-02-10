import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;
import '../../app/services/cache/audio_cache_service.dart';
import '../../components/index.dart';

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> with SignalsMixin {
  late final _audioCacheSize = createSignal(0);
  late final _artworkCacheSize = createSignal(0);
  late final _lyricsCacheSize = createSignal(0);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
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

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '缓存设置',
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
                AppSettingTile(
                  title: '音频缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${_formatSize(_audioCacheSize.value)}',
                  trailing: Icon(Icons.music_note_outlined),
                  onTap: _loading.value ? null : _clearAudioCache,
                ),
                AppSettingTile(
                  title: '封面缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${_formatSize(_artworkCacheSize.value)}',
                  trailing: const Icon(Icons.image_outlined),
                  onTap: _loading.value ? null : _clearArtworkCache,
                ),
                AppSettingTile(
                  title: '歌词缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${_formatSize(_lyricsCacheSize.value)}',
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
          ],
        ),
      ),
    );
  }
}
