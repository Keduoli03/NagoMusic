import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../app/services/local_music_service.dart';
import '../../components/index.dart';

class LocalSourceSettingsPage extends StatefulWidget {
  const LocalSourceSettingsPage({super.key});

  @override
  State<LocalSourceSettingsPage> createState() =>
      _LocalSourceSettingsPageState();
}

class _LocalSourceSettingsPageState extends State<LocalSourceSettingsPage> {
  final LocalMusicService _service = LocalMusicService();
  final ValueNotifier<LocalScanProgress> _scanNotifier =
      ValueNotifier(const LocalScanProgress(processed: 0, added: 0, total: 0));

  bool _loading = true;
  bool _isScanning = false;
  bool _cancelScan = false;
  int _localCount = 0;
  LocalSourceSettings _settings = LocalSourceSettings.defaults();
  List<AssetPathEntity> _albums = [];
  Map<String, int> _albumCounts = {};

  @override
  void dispose() {
    _scanNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _service.loadSettings();
    final albums =
        await _service.loadAudioAlbums(minDurationMs: settings.minDurationMs);
    final localCount = await _service.getLocalSongCount();
    final counts = <String, int>{};
    for (final album in albums) {
      counts[album.id] = await album.assetCountAsync;
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _albums = albums;
      _albumCounts = counts;
      _localCount = localCount;
      _loading = false;
    });
  }

  Future<void> _saveSettings(LocalSourceSettings settings) async {
    setState(() => _settings = settings);
    await _service.saveSettings(settings);
  }

  Future<void> _reloadAlbums() async {
    final albums =
        await _service.loadAudioAlbums(minDurationMs: _settings.minDurationMs);
    final counts = <String, int>{};
    for (final album in albums) {
      counts[album.id] = await album.assetCountAsync;
    }
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _albumCounts = counts;
    });
  }

  void _toggleMode(bool value) {
    _saveSettings(_settings.copyWith(useSystemLibrary: value));
  }

  void _toggleCacheArtwork(bool value) {
    _saveSettings(_settings.copyWith(cacheArtwork: value));
  }

  void _toggleAlbum(String albumId) {
    final include = _settings.includeAlbumIds.toSet();
    if (include.contains(albumId)) {
      include.remove(albumId);
    } else {
      include.add(albumId);
    }
    _saveSettings(_settings.copyWith(includeAlbumIds: include.toList()));
  }

  Future<void> _addCustomFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;
    final current = _settings.includePaths.toList();
    if (current.contains(path)) {
      if (!mounted) return;
      AppToast.show(context, '该文件夹已添加');
      return;
    }
    current.add(path);
    _saveSettings(_settings.copyWith(includePaths: current));
  }

  void _removeCustomFolder(String path) {
    final next = _settings.includePaths.toList()..remove(path);
    _saveSettings(_settings.copyWith(includePaths: next));
  }

  Future<void> _updateMinDuration(double value) async {
    final ms = (value * 1000).round();
    await _saveSettings(_settings.copyWith(minDurationMs: ms));
    await _reloadAlbums();
  }

  void _showScanDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return ValueListenableBuilder<LocalScanProgress>(
          valueListenable: _scanNotifier,
          builder: (context, progress, child) {
            return SourceScanDialog(
              processed: progress.processed,
              added: progress.added,
              total: progress.total,
              isScanning: _isScanning,
              onCancel: () {
                _cancelScan = true;
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              onHide: () {},
            );
          },
        );
      },
    );
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    if (!_settings.useSystemLibrary &&
        _settings.includeAlbumIds.isEmpty &&
        _settings.includePaths.isEmpty) {
      AppToast.show(context, '请先选择扫描文件夹');
      return;
    }
    setState(() {
      _isScanning = true;
      _cancelScan = false;
    });
    _scanNotifier.value =
        const LocalScanProgress(processed: 0, added: 0, total: 0);
    _showScanDialog();
    final result = await _service.scan(
      settings: _settings,
      isCancelled: () => _cancelScan,
      onProgress: (progress) => _scanNotifier.value = progress,
    );
    await _service.saveLastScanCount(result.added);
    if (!mounted) return;
    final count = await _service.getLocalSongCount();
    if (!mounted) return;
    final progress = _scanNotifier.value;
    setState(() {
      _isScanning = false;
      _localCount = count;
    });
    _scanNotifier.value = LocalScanProgress(
      processed: progress.processed,
      added: progress.added,
      total: progress.total,
    );
    if (_cancelScan) {
      AppToast.show(context, '已取消扫描');
      return;
    }
    if (result.processed == 0) {
      AppToast.show(context, '未扫描到歌曲');
      return;
    }
    AppToast.show(context, '成功添加 ${result.added} 首歌', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final minSeconds = (_settings.minDurationMs / 1000).clamp(0.0, 180.0);
    final includeSet = _settings.includeAlbumIds.toSet();
    final includePaths = _settings.includePaths;

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '本地音源设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppSettingSection(
            title: '扫描操作',
            children: [
              AppSettingTile(
                title: _isScanning ? '正在扫描' : '开始扫描',
                subtitle: _isScanning ? '请稍候' : '已收录 $_localCount 首歌曲',
                trailing: _isScanning
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: Icon(Icons.play_arrow_rounded)),
                      ),
                onTap: _isScanning ? null : _startScan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            children: [
              AppSettingSwitchTile(
                title: '扫描系统媒体库',
                subtitle: '开启后默认扫描系统音乐文件夹',
                value: _settings.useSystemLibrary,
                onChanged: _toggleMode,
              ),
              AppSettingSlider(
                title: '最短时长',
                value: minSeconds,
                min: 0,
                max: 180,
                divisions: 18,
                valueText: '${minSeconds.toStringAsFixed(0)} 秒',
                onChanged: _updateMinDuration,
              ),
              AppSettingSwitchTile(
                title: '缓存封面',
                subtitle: '扫描时压缩并缓存本地封面',
                value: _settings.cacheArtwork,
                onChanged: _toggleCacheArtwork,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_settings.useSystemLibrary) ...[
            const SizedBox(height: 16),
            AppSettingSection(
              title: '自定义扫描文件夹',
              children: [
                AppSettingTile(
                  title: '添加文件夹',
                  subtitle: '扫描自定义目录中的音频文件',
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _addCustomFolder,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                  onTap: _addCustomFolder,
                ),
                if (includePaths.isEmpty)
                  const AppSettingTile(title: '暂无自定义文件夹')
                else
                  ...includePaths.map(
                    (path) => AppSettingTile(
                      title: p.basename(path),
                      subtitle: path,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeCustomFolder(path),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppSettingSection(
              title: '系统音频文件夹',
              children: _albums.isEmpty
                  ? [
                      const AppSettingTile(title: '未发现本地音频文件夹'),
                    ]
                  : _albums
                      .map(
                        (album) => AppSettingCheckboxTile(
                          title: album.name,
                          subtitle: '${_albumCounts[album.id] ?? 0} 首',
                          value: includeSet.contains(album.id),
                          onChanged: (_) => _toggleAlbum(album.id),
                        ),
                      )
                      .toList(),
            ),
          ],
          if (_settings.useSystemLibrary)
            AppSettingSection(
              title: '扫描范围',
              children: const [
                AppSettingTile(
                  title: '系统媒体库',
                  subtitle: '将自动扫描所有音频文件夹',
                ),
              ],
            ),
        ],
      ),
    );
  }
}
