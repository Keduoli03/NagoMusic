import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/database/database_helper.dart';
import '../../core/storage/storage_keys.dart';
import '../../core/storage/storage_util.dart';
import '../../models/music_entity.dart';
import '../../viewmodels/library_viewmodel.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_list_tile.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/artwork_widget.dart';
import '../../widgets/blocked_folders_sheet.dart';
import '../../widgets/multi_select_bottom_bar.dart';
import '../../widgets/song_detail_sheet.dart';
import '../library_page.dart';

class LocalFolderBrowser extends StatefulWidget {
  const LocalFolderBrowser({super.key});

  @override
  State<LocalFolderBrowser> createState() => _LocalFolderBrowserState();
}

class _LocalFolderBrowserState extends State<LocalFolderBrowser> {
  List<FolderInfo> _allFolders = [];
  bool _isLoading = true;
  late bool _showBlockedEntry;

  @override
  void initState() {
    super.initState();
    _showBlockedEntry = StorageUtil.getBoolOrDefault(StorageKeys.showBlockedLocalFolders, defaultValue: true);
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final vm = LibraryViewModel();
    final folders = await vm.getFolders();
    if (mounted) {
      setState(() {
        _allFolders = folders;
        _isLoading = false;
      });
    }
  }

  void _showBlockedFolders() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BlockedFoldersSheet(sourceId: 'local', allFolders: _allFolders);
      },
    ).then((_) {
      // Refresh state when coming back (in case of unblock)
      _loadFolders();
    });
  }

  void _blockFolder(FolderInfo folder) async {
    // If it's a system folder, use ID. If custom, use path (ID is path).
    final vm = LibraryViewModel();
    final source = vm.getOrCreateLocalSource();
    final newExclude = List<String>.from(source.excludeFolders)..add(folder.id);
    final updated = source.copyWith(excludeFolders: newExclude);
    
    await vm.upsertSource(updated);
    
    if (mounted) {
      AppToast.show(context, '已屏蔽文件夹: ${folder.name}', type: ToastType.success);
      _loadFolders(); // Refresh list
    }
  }

  void _showFolderMenu(FolderInfo folder, Offset offset) {
    final theme = Theme.of(context);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + 1,
        offset.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.cardColor,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'path',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: theme.iconTheme.color),
              const SizedBox(width: 12),
              const Text('查看路径'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.folder_off, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 12),
                      Text('屏蔽文件夹', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'block') {
        _blockFolder(folder);
      } else if (value == 'path') {
        _showPathDialog(folder);
      }
    });
  }

  Future<void> _showPathDialog(FolderInfo folder) async {
    String path = '未知路径';
    
    if (!folder.isSystem) {
      path = folder.id; // Custom folder ID is path
    } else if (folder.entity != null) {
      // System folder: try to get path from first asset
      final list = await folder.entity!.getAssetListRange(start: 0, end: 1);
      if (list.isNotEmpty) {
        final file = await list.first.file;
        if (file != null) {
          path = file.parent.path;
        }
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AppDialog(
        title: folder.name,
        content: SelectableText(path),
        confirmText: '确定',
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSheet) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(77),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.folder_off),
                    title: const Text('显示已屏蔽文件夹'),
                    value: _showBlockedEntry,
                    onChanged: (value) {
                      setState(() {
                        _showBlockedEntry = value;
                        StorageUtil.setBool(StorageKeys.showBlockedLocalFolders, value);
                      });
                      setStateSheet(() {});
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_input_component),
                    title: const Text('扫描设置'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LibraryPage()),
                      ).then((_) => _loadFolders());
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      watchSignal(context, vm.scanTick);
      final source = vm.getOrCreateLocalSource();
      final exclude = source.excludeFolders.toSet();

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

      final visibleFolders = _allFolders.where((f) {
        if (exclude.contains(f.id)) return false;
        return true;
      }).toList();

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('本地管理'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: _showSettings,
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: background),
          child: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    children: [
                      if (_showBlockedEntry && exclude.isNotEmpty)
                        Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 0,
                          color: Theme.of(context).cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            leading: const Icon(Icons.folder_off, color: Colors.grey),
                            title: Text('已屏蔽 ${exclude.length} 个文件夹'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _showBlockedFolders,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      if (visibleFolders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('没有可见的音乐文件夹')),
                        )
                      else
                        Card(
                          elevation: 0,
                          color: Theme.of(context).cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            children: visibleFolders.asMap().entries.map((entry) {
                              final index = entry.key;
                              final folder = entry.value;
                              final isLast = index == visibleFolders.length - 1;

                              return Column(
                                children: [
                                  GestureDetector(
                                    onLongPressStart: (details) {
                                      _showFolderMenu(folder, details.globalPosition);
                                    },
                                    child: AppListTile(
                                      leading: const Icon(Icons.folder),
                                      title: folder.name,
                                      subtitle: '${folder.count} 首歌曲',
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => _FolderSongsPage(folder: folder),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      indent: 56,
                                      endIndent: 16,
                                      color: Theme.of(context).dividerColor.withAlpha(26),
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      );
    },);
  }
}


class _FolderSongsPage extends StatefulWidget {
  final FolderInfo folder;
  const _FolderSongsPage({required this.folder});

  @override
  State<_FolderSongsPage> createState() => _FolderSongsPageState();
}

class _FolderSongsPageState extends State<_FolderSongsPage> {
  // Sort options
  static const _sortTitle = 'title';
  static const _sortArtist = 'artist';
  static const _sortDate = 'date';
  String _sortOption = _sortTitle;
  bool _sortAscending = true;

  // Multi-select state
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = {};
  bool _isSequentialPlay = false;

  // Data state
  List<MusicEntity> _rawSongs = [];
  List<MusicEntity> _songs = [];
  bool _isLoading = true;
  EffectCleanup? _cleanup;

  // System path cache
  String? _systemPath;
  bool _isLoadingPath = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    // If system folder, load path first
    if (widget.folder.isSystem && widget.folder.entity != null) {
      _loadSystemPath();
    }

    // Subscribe to signals for auto-reload
    _cleanup = effect(() {
      final vm = LibraryViewModel();
      // subscribe to signals
      vm.libraryTick.value;
      vm.scanTick.value;
      
      // Trigger load
      Future.microtask(() => _loadSongs());
    });
  }

  Future<void> _loadSystemPath() async {
    setState(() => _isLoadingPath = true);
    final path = await _resolveSystemFolderPath(widget.folder.entity!);
    if (mounted) {
      setState(() {
        _systemPath = path;
        _isLoadingPath = false;
      });
      // Path loaded, reload songs
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    if (!mounted) return;
    
    // Determine path
    String? path;
    if (widget.folder.isSystem) {
      if (_systemPath == null) return; // Wait for system path
      path = _systemPath;
    } else {
      path = widget.folder.id;
    }

    if (path == null) return;

    // We can show loading state if desired, or just update silently
    // setState(() => _isLoading = true);

    try {
      final songs = await DatabaseHelper().getLocalSongsInFolder(path);
      
      // Get min duration setting
      final vm = LibraryViewModel();
      final source = vm.getOrCreateLocalSource();
      final minDuration = source.minDurationMs ?? 0;

      // Filter for direct children only
      final normalizedFolder = path.replaceAll('\\', '/');
      final directChildren = songs.where((s) {
        if (s.uri == null) return false;
        
        // Filter by duration
        if (minDuration > 0 && (s.durationMs ?? 0) < minDuration) {
          return false;
        }

        final songPath = s.uri!.replaceAll('\\', '/');
        final songDir = p.dirname(songPath).replaceAll('\\', '/');
        return songDir == normalizedFolder;
      }).toList();

      if (mounted) {
        setState(() {
          _rawSongs = directChildren;
          _songs = _sortSongs(_rawSongs);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading songs from DB: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelect = !_isMultiSelect;
      _selectedIds.clear();
      if (_isMultiSelect) {
        // Hide global mini player if needed?
        // Usually handled by UI checking the state, but this is a local page state.
        // We might need to notify global state if we want to hide the player bar.
        LibraryViewModel().setGlobalMultiSelectMode(true);
      } else {
        LibraryViewModel().setGlobalMultiSelectMode(false);
      }
    });
  }

  @override
  void dispose() {
    _cleanup?.call();
    // Reset global multi-select mode when leaving
    if (_isMultiSelect) {
      LibraryViewModel().setGlobalMultiSelectMode(false);
    }
    super.dispose();
  }

  void _onSort(String option) {
    setState(() {
      if (_sortOption == option) {
        _sortAscending = !_sortAscending;
      } else {
        _sortOption = option;
        _sortAscending = true;
      }
      _songs = _sortSongs(_rawSongs);
    });
  }

  List<MusicEntity> _sortSongs(List<MusicEntity> songs) {
    final sorted = List<MusicEntity>.from(songs);
    sorted.sort((a, b) {
      int result = 0;
      switch (_sortOption) {
        case _sortTitle:
          result = a.title.compareTo(b.title);
          break;
        case _sortArtist:
          result = a.artist.compareTo(b.artist);
          break;
        case _sortDate:
          // fileModifiedMs might be null
          final t1 = a.fileModifiedMs ?? 0;
          final t2 = b.fileModifiedMs ?? 0;
          result = t1.compareTo(t2);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  Future<void> _playRandom(List<MusicEntity> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<MusicEntity>.from(songs)..shuffle();
    await PlayerViewModel().playList(shuffled);
  }

  Future<void> _playSequential(List<MusicEntity> songs) async {
    if (songs.isEmpty) return;
    await PlayerViewModel().playList(songs);
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1F2329)
        : const Color.fromARGB(242, 255, 255, 255);
    final secondaryTextColor =
        isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100);
    final primaryColor = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSheet) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: secondaryTextColor.withAlpha(89),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              sectionTitle('歌曲排序'),
              ListTile(
                leading: Icon(
                  Icons.sort_by_alpha,
                  color: _sortOption == _sortTitle ? primaryColor : secondaryTextColor,
                ),
                title: Text(
                  '按标题',
                  style: TextStyle(
                    color: _sortOption == _sortTitle ? primaryColor : null,
                    fontWeight: _sortOption == _sortTitle
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: _sortOption == _sortTitle
                    ? Icon(
                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: primaryColor,
                      )
                    : null,
                onTap: () {
                  _onSort(_sortTitle);
                  setStateSheet(() {});
                  setState(() {});
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.person_outline,
                  color: _sortOption == _sortArtist ? primaryColor : secondaryTextColor,
                ),
                title: Text(
                  '按歌手',
                  style: TextStyle(
                    color: _sortOption == _sortArtist ? primaryColor : null,
                    fontWeight: _sortOption == _sortArtist
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: _sortOption == _sortArtist
                    ? Icon(
                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: primaryColor,
                      )
                    : null,
                onTap: () {
                  _onSort(_sortArtist);
                  setStateSheet(() {});
                  setState(() {});
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.access_time,
                  color: _sortOption == _sortDate ? primaryColor : secondaryTextColor,
                ),
                title: Text(
                  '按修改时间',
                  style: TextStyle(
                    color: _sortOption == _sortDate ? primaryColor : null,
                    fontWeight: _sortOption == _sortDate
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: _sortOption == _sortDate
                    ? Icon(
                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: primaryColor,
                      )
                    : null,
                onTap: () {
                  _onSort(_sortDate);
                  setStateSheet(() {});
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    if (widget.folder.isSystem && widget.folder.entity != null) {
      if (_isLoadingPath) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.folder.name)),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      
      if (_systemPath == null) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.folder.name)),
          body: const Center(child: Text('无法获取文件夹路径')),
        );
      }
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.folder.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return _buildList(context, _songs);
  }

  Future<String?> _resolveSystemFolderPath(AssetPathEntity entity) async {
      final list = await entity.getAssetListRange(start: 0, end: 1);
      if (list.isNotEmpty) {
        final file = await list.first.file;
        if (file != null) {
          return file.parent.path;
        }
      }
      return null;
  }

  Widget _buildList(BuildContext context, List<MusicEntity> songs) {
    final totalCount = songs.length;
    final selectedCount = _selectedIds.length;
    final isAllSelected = selectedCount == totalCount && totalCount > 0;
    
    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelect 
            ? Text('已选择 $selectedCount 项')
            : Text(widget.folder.name),
        actions: [
          if (_isMultiSelect)
             IconButton(
               icon: const Icon(Icons.close),
               onPressed: _toggleMultiSelect,
             ),
        ],
      ),
      body: songs.isEmpty
          ? const Center(child: Text('该文件夹下没有已扫描的歌曲'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  child: Row(
                    children: [
                      _isMultiSelect
                          ? InkWell(
                              onTap: () {
                                if (songs.isEmpty) return;
                                setState(() {
                                  if (isAllSelected) {
                                    _selectedIds.clear();
                                  } else {
                                    _selectedIds.addAll(songs.map((e) => e.id));
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Row(
                                children: [
                                  Icon(
                                    isAllSelected ? Icons.check_circle : Icons.circle_outlined,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('${isAllSelected ? '取消全选' : '全选'} ($selectedCount/$totalCount)'),
                                ],
                              ),
                            )
                          : InkWell(
                              onTap: () {
                                if (_isSequentialPlay) {
                                  _playSequential(songs);
                                } else {
                                  _playRandom(songs);
                                }
                              },
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _isSequentialPlay = !_isSequentialPlay;
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Row(
                                children: [
                                  Icon(_isSequentialPlay ? Icons.playlist_play : Icons.shuffle, size: 20),
                                  const SizedBox(width: 4),
                                  Text('${_isSequentialPlay ? '顺序播放' : '随机播放'} ($totalCount)'),
                                ],
                              ),
                            ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.sort),
                        onPressed: () => _showSortSheet(context),
                      ),
                      IconButton(
                        icon: Icon(_isMultiSelect ? Icons.checklist : Icons.checklist_rtl),
                        onPressed: _toggleMultiSelect,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final selected = _selectedIds.contains(song.id);
                      
                      return ListTile(
                        leading: _isMultiSelect 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (selected) {
                                          _selectedIds.remove(song.id);
                                        } else {
                                          _selectedIds.add(song.id);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Icon(
                                        selected ? Icons.check_circle : Icons.circle_outlined,
                                        color: selected ? Theme.of(context).primaryColor : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  ArtworkWidget(song: song, size: 48, borderRadius: 4),
                                ],
                              )
                            : ArtworkWidget(song: song, size: 48, borderRadius: 4),
                        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          if (_isMultiSelect) {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(song.id);
                              } else {
                                _selectedIds.add(song.id);
                              }
                            });
                          } else {
                            PlayerViewModel().playList(songs, initialIndex: index);
                          }
                        },
                        onLongPress: () {
                          SongDetailSheet.show(context, song);
                        },
                      );
                    },
                  ),
                ),
                if (_isMultiSelect)
                  MultiSelectBottomBar(
                    actions: [
                      MultiSelectAction(
                        icon: Icons.playlist_play,
                        label: '下一首播放',
                        onTap: selectedCount == 0 ? null : () {
                          final selectedSongs = songs.where((s) => _selectedIds.contains(s.id)).toList();
                          PlayerViewModel().insertNext(selectedSongs);
                          _toggleMultiSelect();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已添加 ${selectedSongs.length} 首歌曲到下一首播放')),
                          );
                        },
                      ),
                      MultiSelectAction(
                        icon: Icons.playlist_add,
                        label: '添加到歌单',
                        onTap: selectedCount == 0 ? null : () {
                          final selectedSongs = songs.where((s) => _selectedIds.contains(s.id)).toList();
                          _showAddSongsToPlaylistDialog(context, selectedSongs);
                        },
                      ),
                      MultiSelectAction(
                        icon: Icons.delete_outline,
                        label: '移除',
                        isDestructive: true,
                        onTap: selectedCount == 0 ? null : () async {
                          final selectedSongs = songs.where((s) => _selectedIds.contains(s.id)).toList();
                          
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('确认移除'),
                              content: Text('确定要移除选中的 ${selectedSongs.length} 首歌曲吗？\n这将从本地数据库中删除记录。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('移除', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final ids = selectedSongs.map((s) => s.id).toList();
                            await LibraryViewModel().deleteSongs(ids);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已移除 ${selectedSongs.length} 首歌曲')),
                            );
                            _toggleMultiSelect();
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  Future<void> _showAddSongsToPlaylistDialog(BuildContext context, List<MusicEntity> songs) async {
    final vm = LibraryViewModel();
    final playlists = vm.playlists;
    
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无歌单，请先创建歌单')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('将 ${songs.length} 首歌曲添加到歌单'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return ListTile(
                  title: Text(playlist.name),
                  onTap: () async {
                    final songIds = songs.map((s) => s.id).toList();
                    await vm.addSongsToPlaylist(playlist.id, songIds);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加到歌单: ${playlist.name}')),
                      );
                      _toggleMultiSelect();
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // _filterSongsByPath is removed as we use DatabaseHelper to fetch songs
}
