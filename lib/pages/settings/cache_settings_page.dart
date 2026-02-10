import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;
import '../../app/services/cache/audio_cache_service.dart';
import '../../components/index.dart';

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> with SignalsMixin {
  late final _cacheSize = createSignal(0);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    _loading.value = true;
    final size = await AudioCacheService.instance.getCacheSize();
    if (!mounted) return;
    _cacheSize.value = size;
    _loading.value = false;
  }

  Future<void> _clearCache() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除缓存',
      content: '确定要清除所有音频缓存吗？这将需要重新下载音频文件。',
    );
    if (confirmed != true) return;

    _loading.value = true;
    await AudioCacheService.instance.clearCache();
    if (!mounted) return;
    
    await _loadCacheSize();
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
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '缓存设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Watch.builder(
        builder: (context) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            AppSettingSection(
              title: '缓存管理',
              children: [
                AppSettingTile(
                  title: '音频缓存',
                  subtitle: _loading.value
                      ? '计算中...'
                      : '占用空间: ${_formatSize(_cacheSize.value)}',
                  trailing: const Icon(Icons.delete_outline_rounded),
                  onTap: _loading.value ? null : _clearCache,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
