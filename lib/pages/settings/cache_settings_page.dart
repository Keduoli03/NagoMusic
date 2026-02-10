import 'package:flutter/material.dart';
import '../../app/services/cache/audio_cache_service.dart';
import '../../components/index.dart';

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  int _cacheSize = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    setState(() => _loading = true);
    final size = await AudioCacheService.instance.getCacheSize();
    if (!mounted) return;
    setState(() {
      _cacheSize = size;
      _loading = false;
    });
  }

  Future<void> _clearCache() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '清除缓存',
      content: '确定要清除所有音频缓存吗？这将需要重新下载音频文件。',
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppSettingSection(
            title: '缓存管理',
            children: [
              AppSettingTile(
                title: '音频缓存',
                subtitle: _loading ? '计算中...' : '占用空间: ${_formatSize(_cacheSize)}',
                trailing: const Icon(Icons.delete_outline_rounded),
                onTap: _loading ? null : _clearCache,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
