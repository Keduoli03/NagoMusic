import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

import '../../core/storage/storage_keys.dart';
import '../../core/storage/storage_util.dart';
import '../../models/music_entity.dart';
import '../../viewmodels/library_viewmodel.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../widgets/app_list_tile.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/artwork_widget.dart';
import '../../widgets/blocked_folders_sheet.dart';
import '../../widgets/multi_select_bottom_bar.dart';
import '../../widgets/song_detail_sheet.dart';
import 'webdav_page.dart';

class WebDavFolderBrowser extends StatefulWidget {
  final MusicSource source;
  const WebDavFolderBrowser({super.key, required this.source});

  @override
  State<WebDavFolderBrowser> createState() => _WebDavFolderBrowserState();
}

class _WebDavFolderBrowserState extends State<WebDavFolderBrowser> {
  late bool _showBlockedEntry;

  @override
  void initState() {
    super.initState();
    _showBlockedEntry = StorageUtil.getBoolOrDefault(StorageKeys.showBlockedWebDavFolders, defaultValue: true);
  }

  void _showBlockedFolders(List<FolderInfo> allFolders) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BlockedFoldersSheet(sourceId: widget.source.id, allFolders: allFolders);
      },
    );
  }

  Future<void> _blockFolder(String folderPath) async {
    final vm = LibraryViewModel();
    final source = vm.sources.firstWhere(
      (s) => s.id == widget.source.id,
      orElse: () => widget.source,
    );
    final exclude = List<String>.from(source.excludeFolders);
    if (!exclude.contains(folderPath)) {
      exclude.add(folderPath);
      final updated = source.copyWith(excludeFolders: exclude);
      await vm.upsertSource(updated);
      if (mounted) {
        AppToast.show(context, '已屏蔽文件夹: ${folderPath.split('/').last}', type: ToastType.success);
      }
    }
  }

  void _showFolderMenu(String folderPath, Offset tapPosition) {
    final theme = Theme.of(context);
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx,
        tapPosition.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.cardColor,
      elevation: 8,
      items: [
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.folder_off, color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 12),
              Text('屏蔽此文件夹', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'block') {
        _blockFolder(folderPath);
      }
    },);
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.scanTick);
      
      final currentSource = vm.sources.firstWhere(
        (s) => s.id == widget.source.id,
        orElse: () => widget.source,
      );
      
      final folders = <FolderInfo>[];
      final allFolderPaths = <String>{...currentSource.includeFolders};
      final endpoint = currentSource.endpoint ?? '';
      final pContext = p.url;
      final excludeFolders = currentSource.excludeFolders;

      // Extract all unique folder paths from songs
      final sourceSongs = vm.allSongs.where((s) => s.sourceId == widget.source.id && s.uri != null).toList();
      
      for (final song in sourceSongs) {
        var path = song.uri!.replaceAll('\\', '/');
        if (endpoint.isNotEmpty && path.startsWith(endpoint)) {
           path = path.substring(endpoint.length);
           if (!path.startsWith('/')) path = '/$path';
        }
        try { path = Uri.decodeFull(path); } catch (_) {}
        
        final dir = pContext.dirname(path).replaceAll('\\', '/');
        
        // Add directory and parents if they are within any includeFolder
        for (final root in currentSource.includeFolders) {
            // Normalize root for comparison
            final normalizedRoot = root.replaceAll('\\', '/');
            if (dir == normalizedRoot || pContext.isWithin(normalizedRoot, dir)) {
                var current = dir;
                // Add path and walk up to root
                while (true) {
                    allFolderPaths.add(current);
                    if (current == normalizedRoot) break;
                    final parent = pContext.dirname(current).replaceAll('\\', '/');
                    if (parent == current) break; // Root reached
                    if (!pContext.isWithin(normalizedRoot, parent) && parent != normalizedRoot) break;
                    current = parent;
                }
            }
        }
      }

      for (final path in allFolderPaths) {
         final subFolders = currentSource.includeFolders.where((other) {
            final normalizedOther = other.replaceAll('\\', '/');
            if (normalizedOther == path) return false;
            return pContext.isWithin(path, normalizedOther);
         }).toList();

         final count = _countSongsInFolder(vm.allSongs, path, excludePaths: subFolders);
        folders.add(
          FolderInfo(
            id: path,
            name: path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path,
            count: count,
            isSystem: false,
          ),
        );
      }

      // Sort: Roots first, then alphabetical
      folders.sort((a, b) {
          final aIsRoot = currentSource.includeFolders.contains(a.id);
          final bIsRoot = currentSource.includeFolders.contains(b.id);
          if (aIsRoot && !bIsRoot) return -1;
          if (!aIsRoot && bIsRoot) return 1;
          return a.name.compareTo(b.name);
      });

      final visibleFolders = folders.where((f) => !excludeFolders.contains(f.id)).toList();

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
          title: Text(currentSource.name),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'WebDAV 设置',
              onPressed: () {
                _showSettings(context, currentSource);
              },
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: background),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                if (_showBlockedEntry && excludeFolders.isNotEmpty)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.folder_off, color: Colors.grey),
                      title: Text('已屏蔽 ${excludeFolders.length} 个文件夹'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showBlockedFolders(folders),
                    ),
                  ),
                
                if (visibleFolders.isEmpty)
                   const SizedBox(
                     height: 200,
                     child: Center(child: Text('没有显示的文件夹')),
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
                                _showFolderMenu(folder.id, details.globalPosition);
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
                                      builder: (_) => WebDavFolderSongsPage(
                                        folder: folder,
                                        sourceId: currentSource.id,
                                      ),
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

  void _showSettings(BuildContext context, MusicSource source) {
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
                        StorageUtil.setBool(StorageKeys.showBlockedWebDavFolders, value);
                      });
                      setStateSheet(() {});
                    },
                  ),
                  ListTile(
                     leading: const Icon(Icons.settings_input_component),
                     title: const Text('云盘设置'),
                     onTap: () {
                       Navigator.pop(context);
                       Navigator.push(
                         context,
                         MaterialPageRoute(builder: (_) => WebDavPage(source: source)),
                       );
                     },
                  ),
                  // Add more settings here if needed (e.g. edit connection)
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _countSongsInFolder(List<MusicEntity> songs, String folderPath, {List<String> excludePaths = const []}) {
    String normalize(String value) => value.replaceAll('\\', '/');
    final normalizedFolder = normalize(folderPath);
    final prefix = normalizedFolder.endsWith('/') ? normalizedFolder : '$normalizedFolder/';
    
    final excludePrefixes = excludePaths.map((p) {
        final np = normalize(p);
        return np.endsWith('/') ? np : '$np/';
    }).toList();

    final endpoint = widget.source.endpoint ?? '';

    return songs.where((s) {
      if (s.sourceId != widget.source.id) return false;
      final uri = s.uri;
      if (uri == null || uri.isEmpty) return false;
      
      var songPath = normalize(uri);
      
      // If uri contains endpoint, strip it to get relative path
      if (endpoint.isNotEmpty && songPath.startsWith(endpoint)) {
         songPath = songPath.substring(endpoint.length);
         if (!songPath.startsWith('/')) songPath = '/$songPath';
      }
      
      // Decode URL to handle spaces and special characters
      try {
        songPath = Uri.decodeFull(songPath);
      } catch (_) {
        // Ignore decode errors
      }

      if (songPath != normalizedFolder && !songPath.startsWith(prefix)) return false;
      
      for (final ex in excludePrefixes) {
          if (songPath.startsWith(ex)) return false;
      }
      return true;
    }).length;
  }
}

class WebDavFolderSongsPage extends StatefulWidget {
  final FolderInfo folder;
  final String sourceId;
  const WebDavFolderSongsPage({super.key, required this.folder, required this.sourceId});

  @override
  State<WebDavFolderSongsPage> createState() => _WebDavFolderSongsPageState();
}

class _WebDavFolderSongsPageState extends State<WebDavFolderSongsPage> {
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

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelect = !_isMultiSelect;
      _selectedIds.clear();
      if (_isMultiSelect) {
        LibraryViewModel().setGlobalMultiSelectMode(true);
      } else {
        LibraryViewModel().setGlobalMultiSelectMode(false);
      }
    },);
  }

  @override
  void dispose() {
    if (_isMultiSelect) {
      LibraryViewModel().setGlobalMultiSelectMode(false);
    }
    super.dispose();
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
          final t1 = a.fileModifiedMs ?? 0;
          final t2 = b.fileModifiedMs ?? 0;
          result = t1.compareTo(t2);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    },);
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

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.scanTick);

      final allSongs = vm.allSongs;
      String endpoint = '';
      
      // Find current source to get exclude paths (nested folders) and endpoint
      List<String> subFolders = [];
      try {
        final source = vm.sources.firstWhere((s) => s.id == widget.sourceId);
        endpoint = source.endpoint ?? '';
        final pContext = p.url;
        final normalizedCurrent = widget.folder.id.replaceAll('\\', '/');

        subFolders = source.includeFolders.where((other) {
           final normalizedOther = other.replaceAll('\\', '/');
           if (normalizedOther == normalizedCurrent) return false;
           return pContext.isWithin(normalizedCurrent, normalizedOther);
        }).toList();
      } catch (_) {
        // Source might be missing or not found
      }

      final filtered = _filterSongsByPath(allSongs, widget.folder.id, widget.sourceId, endpoint, excludePaths: subFolders);
      final songs = _sortSongs(filtered);
      final totalCount = songs.length;
      final selectedCount = _selectedIds.length;
      final isAllSelected = totalCount > 0 && selectedCount == totalCount;

      return Scaffold(
        appBar: AppBar(
          title: Text(widget.folder.name),
        ),
        body: Column(
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
              child: songs.isEmpty
                  ? const Center(child: Text('该文件夹下没有已扫描的歌曲'))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final isSelected = _selectedIds.contains(song.id);
                        return ListTile(
                          leading: _isMultiSelect
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected) {
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
                                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                                          size: 20,
                                          color: isSelected
                                              ? Theme.of(context).colorScheme.primary
                                              : Theme.of(context).disabledColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ArtworkWidget(song: song, size: 48, borderRadius: 6),
                                  ],
                                )
                              : ArtworkWidget(song: song, size: 48, borderRadius: 6),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            if (_isMultiSelect) {
                              setState(() {
                                if (isSelected) {
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
                    icon: Icons.queue_play_next,
                    label: '下一首播放',
                    onTap: selectedCount == 0 ? null : () {
                      final selected = songs.where((s) => _selectedIds.contains(s.id)).toList();
                      PlayerViewModel().insertNext(selected);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加 ${selected.length} 首歌曲到下一首播放')),
                      );
                      _toggleMultiSelect();
                    },
                  ),
                  MultiSelectAction(
                    icon: Icons.playlist_add,
                    label: '添加到歌单',
                    onTap: selectedCount == 0 ? null : () {
                      final selected = songs.where((s) => _selectedIds.contains(s.id)).toList();
                      _showAddSongsToPlaylistDialog(context, selected);
                    },
                  ),
                  MultiSelectAction(
                    icon: Icons.delete_outline,
                    label: '移除',
                    isDestructive: true,
                    onTap: selectedCount == 0 ? null : () async {
                      final selected = songs.where((s) => _selectedIds.contains(s.id)).toList();
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('确认移除'),
                          content: Text('确定要移除选中的 ${selected.length} 首歌曲吗？\n这将从本地数据库中删除记录。'),
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
                        final ids = selected.map((s) => s.id).toList();
                        await LibraryViewModel().deleteSongs(ids);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已移除 ${selected.length} 首歌曲')),
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
    },);
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
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            Widget buildGridOption({
              required String label,
              required IconData icon,
              required bool selected,
              required VoidCallback onTap,
              bool alignRight = false,
            }) {
              final color = selected ? primaryColor : secondaryTextColor;
              final bgColor = selected
                  ? primaryColor.withAlpha(((isDark ? 0.18 : 0.12) * 255).round())
                  : Colors.transparent;
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: alignRight ? TextAlign.right : TextAlign.left,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget row(Widget left, Widget right) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [left, right],
                  ),
                ),
              );
            }

            Widget sectionTitle(String text) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  text,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            return SafeArea(
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final contentWidth = (maxWidth - 56).clamp(0.0, maxWidth).toDouble();
                      return Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              row(
                                buildGridOption(
                                  label: '歌曲名称',
                                  icon: Icons.sort_by_alpha,
                                  selected: _sortOption == _sortTitle,
                                  onTap: () {
                                    setState(() => _sortOption = _sortTitle);
                                    setStateSheet(() {});
                                  },
                                ),
                                buildGridOption(
                                  label: '歌手名称',
                                  icon: Icons.person_outline,
                                  selected: _sortOption == _sortArtist,
                                  onTap: () {
                                    setState(() => _sortOption = _sortArtist);
                                    setStateSheet(() {});
                                  },
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '最近修改',
                                  icon: Icons.update,
                                  selected: _sortOption == _sortDate,
                                  onTap: () {
                                    setState(() => _sortOption = _sortDate);
                                    setStateSheet(() {});
                                  },
                                ),
                                const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  sectionTitle('排序方式'),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final contentWidth = (maxWidth - 96).clamp(0.0, maxWidth).toDouble();
                      return Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              buildGridOption(
                                label: '升序',
                                icon: Icons.arrow_upward,
                                selected: _sortAscending,
                                onTap: () {
                                  setState(() => _sortAscending = true);
                                  setStateSheet(() {});
                                },
                              ),
                              buildGridOption(
                                label: '降序',
                                icon: Icons.arrow_downward,
                                selected: !_sortAscending,
                                onTap: () {
                                  setState(() => _sortAscending = false);
                                  setStateSheet(() {});
                                },
                                alignRight: true,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }



  Future<void> _showAddSongsToPlaylistDialog(
    BuildContext context,
    List<MusicEntity> songs,
  ) async {
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
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加到歌单: ${playlist.name}')),
                    );
                    _toggleMultiSelect();
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

  List<MusicEntity> _filterSongsByPath(
    List<MusicEntity> allSongs,
    String folderPath,
    String sourceId,
    String endpoint,
    {List<String> excludePaths = const [],}
  ) {
    String normalize(String value) => value.replaceAll('\\', '/');
    final normalizedFolder = normalize(folderPath);
    final prefix = normalizedFolder.endsWith('/') ? normalizedFolder : '$normalizedFolder/';

    final excludePrefixes = excludePaths.map((p) {
        final np = normalize(p);
        return np.endsWith('/') ? np : '$np/';
    }).toList();

    return allSongs.where((s) {
      if (s.sourceId != sourceId) return false;
      final uri = s.uri;
      if (uri == null || uri.isEmpty) return false;
      
      var songPath = normalize(uri);
      
      if (endpoint.isNotEmpty && songPath.startsWith(endpoint)) {
         songPath = songPath.substring(endpoint.length);
         if (!songPath.startsWith('/')) songPath = '/$songPath';
      }

      // Decode URL to handle spaces and special characters
      try {
        songPath = Uri.decodeFull(songPath);
      } catch (_) {
        // Ignore decode errors
      }

      if (songPath != normalizedFolder && !songPath.startsWith(prefix)) return false;
      
      for (final ex in excludePrefixes) {
          if (songPath.startsWith(ex)) return false;
      }
      return true;
    }).toList();
  }
}
