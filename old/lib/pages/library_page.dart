import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vibe_music/widgets/app_toast.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../models/music_entity.dart';
import '../viewmodels/library_viewmodel.dart';
import '../widgets/labeled_slider.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late MusicSource _source;
  double _minDurationValue = 0.0;
  bool _useSystemLibrary = true;
  int _localMetadataConcurrency = 6;
  
  final Set<String> _include = {};
  final Set<String> _exclude = {};

  @override
  void initState() {
    super.initState();
    final vm = LibraryViewModel();
    _source = vm.getOrCreateLocalSource();
    _include.addAll(_source.includeFolders);
    _exclude.addAll(_source.excludeFolders);
    _useSystemLibrary = _source.useSystemLibrary;
    if (_source.minDurationMs != null) {
      _minDurationValue = (_source.minDurationMs! / 1000).clamp(0.0, 180.0);
    }
    _localMetadataConcurrency = StorageUtil.getIntOrDefault(
      StorageKeys.localMetadataConcurrency,
      defaultValue: 6,
    );
    if (_localMetadataConcurrency < 1) {
      _localMetadataConcurrency = 1;
    }
  }

  Future<void> _updateSource() async {
    final vm = LibraryViewModel();
    final minMs = _minDurationValue > 0 ? (_minDurationValue * 1000).toInt() : null;
    
    final updated = _source.copyWith(
      includeFolders: _include.toList(),
      excludeFolders: _exclude.toList(),
      minDurationMs: minMs,
      useSystemLibrary: _useSystemLibrary,
    );
    await vm.upsertSource(updated);
    _source = updated;
  }

  Future<void> _pickCustomFolder() async {
    final String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null && path.isNotEmpty) {
      setState(() {
        _include.add(path);
      });
      _updateSource();
    }
  }

  Future<void> _handleScan() async {
    var dialogOpen = true;
    final dialogFuture = showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        content: Watch.builder(builder: (context) {
          final vm = LibraryViewModel();
          watchSignal(context, vm.scanTick);
          final isLoading = vm.isLoading;
          final processed = vm.scanProcessedCount;
          final added = vm.scanAddedCount;
          final summary = isLoading ? '正在扫描...' : '扫描完成';
          final detail =
              processed == 0 ? '' : '已扫描 $processed 首，已添加 $added 首';
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      summary,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (!dialogOpen) return;
                      dialogOpen = false;
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
                    child: Text(isLoading ? '隐藏' : '完成'),
                  ),
                ],
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    detail,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          );
        },),
      ),
    );
    dialogFuture.whenComplete(() {
      dialogOpen = false;
    });

    final vm = LibraryViewModel();
    var addedCount = 0;
    await _updateSource();
    addedCount = await vm.scanSource(_source);
    
    if (mounted) {
      AppToast.show(context, '连接成功，已添加 $addedCount 首歌', type: ToastType.success);
    }
  }

  Widget _customListItem({
    required Widget leading,
    required Widget title,
    required Widget trailing,
    Widget? subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 32, 12),
          child: Row(
            children: [
              IconTheme(
                data: IconThemeData(
                  color: Theme.of(context).iconTheme.color,
                  size: 24,
                ),
                child: leading,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                        child: subtitle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              trailing,
            ],
          ),
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
        title: const Text('本地设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: FutureBuilder<List<AssetPathEntity>>(
          future: _foldersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Scan Section
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.refresh),
                      title: const Text('开始扫描'),
                      onTap: _handleScan,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Custom Folders
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        '自定义文件夹',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white70 
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_include.isNotEmpty)
                          ..._include.map((path) {
                            return Column(
                              children: [
                                _customListItem(
                                  leading: const Icon(Icons.folder_open),
                                  title: Text(p.basename(path)),
                                  subtitle: Text(path),
                                  trailing: GestureDetector(
                                    onTap: () {
                                      setState(() => _include.remove(path));
                                      _updateSource();
                                    },
                                    child: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                ),
                                Divider(
                                  height: 1, 
                                  indent: 56, 
                                  endIndent: 16,
                                  color: Theme.of(context).dividerColor.withAlpha(26),
                                ),
                              ],
                            );
                          }),
                        
                        _customListItem(
                          leading: const Icon(Icons.create_new_folder_outlined),
                          title: const Text('添加自定义文件夹'),
                          subtitle: const Text('从存储中选择一个文件夹'),
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Theme.of(context).hintColor,
                          ),
                          onTap: _pickCustomFolder,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  // 3. Settings
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SwitchListTile(
                      title: const Text('使用安卓媒体库'),
                      subtitle: const Text('自动扫描系统媒体文件夹'),
                      value: _useSystemLibrary,
                      onChanged: (v) {
                        setState(() => _useSystemLibrary = v);
                        _updateSource();
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LabeledSlider(
                          title: '过滤时长',
                          value: _minDurationValue,
                          min: 0,
                          max: 180,
                          divisions: 180,
                          label: '${_minDurationValue.toInt()}s',
                          tickCount: 19,
                          valueText: '${_minDurationValue.toInt()}s',
                          description: '0 表示不过滤，短于该时长的歌曲将忽略',
                          onChanged: (v) => setState(() => _minDurationValue = v),
                          onChangeEnd: (v) => _updateSource(),
                          titleWidth: 84,
                        ),
                        const SizedBox(height: 12),
                        LabeledSlider(
                          title: '标签并发',
                          value: _localMetadataConcurrency.toDouble(),
                          min: 1,
                          max: 12,
                          divisions: 11,
                          label: '$_localMetadataConcurrency',
                          valueText: '$_localMetadataConcurrency',
                          description: '并发越高更新越快，但更耗资源',
                          onChanged: (v) {
                            setState(() {
                              _localMetadataConcurrency = v.round();
                            });
                          },
                          onChangeEnd: (v) async {
                            final value = v.round() < 1 ? 1 : v.round();
                            await StorageUtil.setInt(
                              StorageKeys.localMetadataConcurrency,
                              value,
                            );
                          },
                          titleWidth: 84,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

}

class LocalFoldersPage extends StatefulWidget {
  const LocalFoldersPage({super.key});

  @override
  State<LocalFoldersPage> createState() => _LocalFoldersPageState();
}

class _LocalFoldersPageState extends State<LocalFoldersPage> {
  String _currentPath = '';
  String _rootPath = '';
  List<AssetPathEntity> _folders = [];
  Map<String, int> _folderBytes = {};
  bool _loadingSizes = false;
  String _sizesKey = '';

  String _resolveRoot(List<String> paths) {
    for (final pth in paths) {
      if (pth.startsWith('/storage/emulated/0')) return '/storage/emulated/0';
    }
    for (final pth in paths) {
      if (pth.startsWith('/storage')) return '/storage';
    }
    if (paths.isNotEmpty) {
      final dir = p.dirname(paths.first);
      final parts = p.split(dir);
      if (parts.length >= 2) {
        return p.join(parts[0], parts[1]);
      }
      return dir;
    }
    return p.separator;
  }

  Future<void> _ensureFolders(LibraryViewModel vm) async {
    if (_folders.isNotEmpty) return;
    final list = await vm.loadLocalFolders();
    if (!mounted) return;
    setState(() => _folders = list);
  }

  String _buildSizesKey(List<MusicEntity> songs) {
    var hash = 0;
    for (final s in songs) {
      final uri = s.uri ?? '';
      hash = 0x1fffffff & (hash + uri.hashCode);
    }
    return '${songs.length}-$hash';
  }

  Future<void> _loadSizes(List<MusicEntity> songs, String rootPath) async {
    if (_loadingSizes) return;
    _loadingSizes = true;
    final bytesByFolder = <String, int>{};
    for (final s in songs) {
      final uri = s.uri;
      if (uri == null || uri.isEmpty) continue;
      int size = 0;
      try {
        size = await File(uri).length();
      } catch (_) {}
      var dir = p.dirname(uri);
      while (true) {
        bytesByFolder[dir] = (bytesByFolder[dir] ?? 0) + size;
        if (dir == rootPath || dir == p.separator || dir.isEmpty || dir == p.rootPrefix(dir)) break;
        final parent = p.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    if (!mounted) return;
    setState(() {
      _folderBytes = bytesByFolder;
      _loadingSizes = false;
    },);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    final value = size < 10 && idx > 0 ? size.toStringAsFixed(1) : size.toStringAsFixed(0);
    return '$value ${units[idx]}';
  }

  String _sizeText(String path) {
    final bytes = _folderBytes[path];
    if (bytes == null) return '计算中';
    return _formatBytes(bytes);
  }

  String _folderName(String id) {
    for (final f in _folders) {
      if (f.id == id) return f.name;
    }
    return id;
  }

  void _showRootMore(MusicSource source) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('内部存储')),
              ListTile(
                title: const Text('存储路径'),
                subtitle: Text(_rootPath),
              ),
              ListTile(
                title: const Text('屏蔽文件夹'),
                subtitle: Text(
                  source.excludeFolders.isEmpty
                      ? '无'
                      : source.excludeFolders.map(_folderName).join('，'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      watchSignal(context, vm.scanTick);
      final localSource = vm.getOrCreateLocalSource();
      final localSongs = vm.songs
        .where((s) => s.isLocal && s.uri != null && s.uri!.isNotEmpty)
        .toList();
    final paths = localSongs.map((s) => s.uri!).toList();
    _rootPath = _resolveRoot(paths);
    if (_currentPath.isEmpty) {
      _currentPath = _rootPath;
    }
    final sizesKey = _buildSizesKey(localSongs);
    if (sizesKey != _sizesKey) {
      _sizesKey = sizesKey;
      _folderBytes = {};
      _loadingSizes = false;
      _loadSizes(localSongs, _rootPath);
    } else if (_folderBytes.isEmpty && !_loadingSizes) {
      _loadSizes(localSongs, _rootPath);
    }
    _ensureFolders(vm);

    if (localSongs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('文件夹')),
        body: const Center(child: Text('暂无本地音乐')),
      );
    }

    final folderCounts = <String, int>{};
    final folderSet = <String>{};
    for (final path in paths) {
      var dir = p.dirname(path);
      while (true) {
        folderCounts[dir] = (folderCounts[dir] ?? 0) + 1;
        folderSet.add(dir);
        if (dir == _rootPath || dir == p.separator || dir.isEmpty || dir == p.rootPrefix(dir)) break;
        final parent = p.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }

    final childFolders = folderSet
        .where((f) => p.dirname(f) == _currentPath && f != _currentPath)
        .toList()
      ..sort();

    final directSongs = localSongs.where((s) {
      final dir = p.dirname(s.uri!);
      return dir == _currentPath;
    }).toList();

      return Scaffold(
      appBar: AppBar(title: const Text('文件夹')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: const Color(0xFFF5F1E8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('内部存储'),
              subtitle: Text('共${localSongs.length}首 · ${_sizeText(_rootPath)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showRootMore(localSource),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                setState(() => _currentPath = _rootPath);
              },
            ),
          ),
          const SizedBox(height: 12),
          ...childFolders.map((folder) {
            final count = folderCounts[folder] ?? 0;
            final name = p.basename(folder);
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(name.isEmpty ? folder : name),
              subtitle: Text('$count 首 · ${_sizeText(folder)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() => _currentPath = folder);
              },
            );
          }),
          if (directSongs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('歌曲'),
            const SizedBox(height: 8),
            ...directSongs.map((s) {
              final name = p.basename(s.uri!);
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(name),
                subtitle: Text(s.artist),
              );
            }),
          ],
        ],
      ),
    );
    },);
  }
}
