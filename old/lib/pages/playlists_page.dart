
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../models/music_entity.dart';
import '../models/playlist_model.dart';
import '../viewmodels/library_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/multi_select_bottom_bar.dart';
import '../widgets/song_detail_sheet.dart';


class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      final playlists = vm.playlists;

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        bottomNavigationBar: null,
        appBar: AppBar(
          title: const Text('歌单'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showCreatePlaylistSheet(context),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                itemCount: playlists.length,
                onReorder: (oldIndex, newIndex) {
                  vm.reorderPlaylists(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    key: ValueKey(playlist.id),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        playlist.isFavorite ? Icons.favorite : Icons.music_note,
                        color: playlist.isFavorite ? Colors.red : null,
                      ),
                    ),
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.songCount ?? 0} 首'),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showPlaylistOptionSheet(context, playlist),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailPage(playlist: playlist),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          ],
        ),
      );
    },);
  }

  void _showCreatePlaylistSheet(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: '新建歌单',
          confirmText: '创建',
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '请输入歌单名称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (value) {
              final name = value.trim();
              if (name.isNotEmpty) {
                LibraryViewModel().createPlaylist(name);
                Navigator.pop(context);
              }
            },
          ),
          onConfirm: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              LibraryViewModel().createPlaylist(name);
            }
          },
        );
      },
    );
  }

  void _showPlaylistOptionSheet(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                if (!playlist.isFavorite)
                  AppListTile(
                    leading: const Icon(Icons.vertical_align_top),
                    title: '置顶',
                    onTap: () {
                      Navigator.pop(context);
                      LibraryViewModel().movePlaylistToTop(playlist.id);
                    },
                  ),
                AppListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: '编辑歌单',
                  subtitle: '修改歌单名称',
                  onTap: () {
                    Navigator.pop(context);
                    _showRenamePlaylistSheet(context, playlist);
                  },
                ),
                if (!playlist.isFavorite)
                  AppListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: '删除歌单',
                    titleColor: Colors.red,
                    subtitle: '删除后无法恢复',
                    onTap: () {
                      Navigator.pop(context);
                      _showDeletePlaylistDialog(context, playlist);
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRenamePlaylistSheet(BuildContext context, Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final theme = Theme.of(context);
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '重命名歌单',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '请输入歌单名称',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    autofocus: true,
                    onSubmitted: (value) {
                      final name = value.trim();
                      if (name.isNotEmpty) {
                        LibraryViewModel().renamePlaylist(playlist.id, name);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: theme.textTheme.bodyMedium,
                        ),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final name = controller.text.trim();
                          if (name.isNotEmpty) {
                            LibraryViewModel().renamePlaylist(playlist.id, name);
                            Navigator.pop(context);
                          }
                        },
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除歌单'),
          content: Text('确定要删除歌单 "${playlist.name}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                LibraryViewModel().deletePlaylist(playlist.id);
                Navigator.pop(context);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  List<MusicEntity> _songs = [];
  List<MusicEntity> _originalSongs = [];
  bool _isLoading = true;
  
  // State for features
  bool _isSequentialPlay = false;
  bool _multiSelect = false;
  final Set<String> _selectedIds = {};
  String _sortKey = 'default';
  bool _sortAscending = true;

  @override
  void dispose() {
    LibraryViewModel().setGlobalMultiSelectMode(false);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs =
        await LibraryViewModel().getSongsInPlaylist(widget.playlist.id);
    if (mounted) {
      setState(() {
        _songs = List.from(songs);
        _originalSongs = List.from(songs);
        _isLoading = false;
        // Re-apply sort if needed
        if (_sortKey != 'default') {
          _sortSongs();
        }
      });
    }
  }

  void _sortSongs() {
    if (_sortKey == 'default') {
      setState(() {
        _songs = List.from(_originalSongs);
      });
      return;
    }

    setState(() {
      _songs.sort((a, b) {
        int cmp;
        switch (_sortKey) {
          case 'title':
            cmp = a.title.compareTo(b.title);
            break;
          case 'artist':
            cmp = a.artist.compareTo(b.artist);
            break;
          case 'album':
            cmp = (a.album ?? '').compareTo(b.album ?? '');
            break;
          default:
            cmp = 0;
        }
        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  void _showSortSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.scaffoldBackgroundColor;
    final primaryColor = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
              final color = selected ? primaryColor : theme.textTheme.bodyMedium?.color;
              final bgColor = selected
                  ? primaryColor.withValues(alpha: isDark ? 0.18 : 0.12)
                  : Colors.transparent;
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: alignRight ? TextAlign.right : TextAlign.left,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget row(Widget left, Widget right) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      left,
                      right,
                    ],
                  ),
                ),
              );
            }

            Widget sectionTitle(String text) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            void applySort(String key) {
              setStateSheet(() {
                if (_sortKey == key) {
                } else {
                  _sortKey = key;
                  _sortAscending = true; 
                }
              });
              _sortSongs();
            }

            void toggleOrder(bool ascending) {
              setStateSheet(() {
                _sortAscending = ascending;
              });
              _sortSongs();
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    sectionTitle('歌曲排序'),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final contentWidth =
                            (maxWidth - 24).clamp(0.0, maxWidth).toDouble();
                        return Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: contentWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                row(
                                  buildGridOption(
                                    label: '添加时间',
                                    icon: Icons.sort,
                                    selected: _sortKey == 'default',
                                    onTap: () => applySort('default'),
                                  ),
                                  buildGridOption(
                                    label: '歌曲名称',
                                    icon: Icons.sort_by_alpha,
                                    selected: _sortKey == 'title',
                                    onTap: () => applySort('title'),
                                    alignRight: true,
                                  ),
                                ),
                                row(
                                  buildGridOption(
                                    label: '歌手名称',
                                    icon: Icons.person_outline,
                                    selected: _sortKey == 'artist',
                                    onTap: () => applySort('artist'),
                                  ),
                                  buildGridOption(
                                    label: '专辑名称',
                                    icon: Icons.album_outlined,
                                    selected: _sortKey == 'album',
                                    onTap: () => applySort('album'),
                                    alignRight: true,
                                  ),
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
                        final contentWidth =
                            (maxWidth - 96).clamp(0.0, maxWidth).toDouble();
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
                                  onTap: () => toggleOrder(true),
                                ),
                                buildGridOption(
                                  label: '降序',
                                  icon: Icons.arrow_downward,
                                  selected: !_sortAscending,
                                  onTap: () => toggleOrder(false),
                                  alignRight: true,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddSongsToPlaylistDialog(List<MusicEntity> songs) async {
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
                      setState(() {
                        _multiSelect = false;
                        _selectedIds.clear();
                      });
                      if (context.mounted) {
                        LibraryViewModel().setGlobalMultiSelectMode(false);
                      }
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


  Future<void> _showRenamePlaylistSheet() async {
    final controller = TextEditingController(text: widget.playlist.name);
    final theme = Theme.of(context);
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '重命名歌单',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: '请输入歌单名称',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    autofocus: true,
                    onSubmitted: (value) {
                      final name = value.trim();
                      if (name.isNotEmpty) {
                        LibraryViewModel().renamePlaylist(widget.playlist.id, name);
                        Navigator.pop(context);
                        setState(() {}); // Refresh title in AppBar
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          final name = controller.text.trim();
                          if (name.isNotEmpty) {
                            LibraryViewModel().renamePlaylist(widget.playlist.id, name);
                            Navigator.pop(context);
                            setState(() {}); // Refresh title in AppBar
                          }
                        },
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Watch.builder(builder: (context) {
          final vm = LibraryViewModel();
          watchSignal(context, vm.settingsTick);
          final theme = Theme.of(context);
          final showCovers = vm.showPlaylistCovers;
          return Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.playlist.isFavorite)
                    AppListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: '编辑歌单',
                      subtitle: '修改歌单名称',
                      onTap: () {
                        Navigator.pop(context);
                        _showRenamePlaylistSheet();
                      },
                    ),
                  if (!widget.playlist.isFavorite)
                    AppListTile(
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: '删除歌单',
                      titleColor: Colors.red,
                      subtitle: '删除后无法恢复',
                      onTap: () {
                        Navigator.pop(context);
                        _showDeletePlaylistDialog();
                      },
                    ),
                  AppListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: '显示封面',
                    subtitle: showCovers ? '当前已开启' : '当前已关闭',
                    trailing: Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: showCovers,
                        onChanged: (value) {
                          vm.setShowPlaylistCovers(value);
                        },
                      ),
                    ),
                    onTap: () {
                      vm.setShowPlaylistCovers(!showCovers);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
        },);
      },
    );
  }

  Future<void> _showDeletePlaylistDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除歌单'),
          content: Text('确定要删除歌单 "${widget.playlist.name}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await LibraryViewModel().deletePlaylist(widget.playlist.id);
                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close page
                }
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final playerVM = PlayerViewModel();
      final libraryVM = LibraryViewModel();
      watchSignal(context, playerVM.queueTick);
      watchSignal(context, playerVM.playbackTick);
      watchSignal(context, libraryVM.libraryTick);
      watchSignal(context, libraryVM.settingsTick);
      final currentSong = playerVM.currentSong;
      final showCovers = libraryVM.showPlaylistCovers;
    
    // Header Row Logic
    final headerRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          // 1. Play Button (Left, Compact)
          if (!_multiSelect)
            InkWell(
              onTap: () {
                if (_songs.isNotEmpty) {
                  if (_isSequentialPlay) {
                    playerVM.playList(_songs);
                  } else {
                    final shuffled = List<MusicEntity>.from(_songs)..shuffle();
                    playerVM.playList(shuffled);
                  }
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
                  Icon(
                    _isSequentialPlay ? Icons.playlist_play : Icons.shuffle,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_isSequentialPlay ? '顺序播放' : '随机播放'} (${_songs.length})',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),

          // Multi-select "Select All" logic (replaces Play button in multi-select mode)
          if (_multiSelect)
            InkWell(
              onTap: () {
                if (_songs.isEmpty) return;
                setState(() {
                  if (_selectedIds.length == _songs.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.clear();
                    _selectedIds.addAll(_songs.map((e) => e.id));
                  }
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  Icon(
                    _selectedIds.length == _songs.length
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedIds.length == _songs.length
                        ? '取消全选 (${_selectedIds.length})'
                        : '全选 (${_selectedIds.length}/${_songs.length})',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // 2. Sort Button
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onPressed: _showSortSheet,
            enableFeedback: true, 
          ),

          // 3. Multi-select Button (Right)
          IconButton(
            icon: Icon(_multiSelect ? Icons.close : Icons.checklist_rtl),
            tooltip: _multiSelect ? '退出多选' : '多选',
            onPressed: () {
              setState(() {
                _multiSelect = !_multiSelect;
                _selectedIds.clear();
              });
              LibraryViewModel().setGlobalMultiSelectMode(_multiSelect);
            },
          ),
        ],
      ),
    );

    // Determine if we can reorder
    // User wants sorting ONLY in multi-select mode
    final canReorder = _multiSelect && _sortKey == 'default';

    Widget buildListItem(int index) {
      final song = _songs[index];
      final isCurrent = currentSong?.id == song.id;
      final isSelected = _selectedIds.contains(song.id);
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final titleColor = isCurrent
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface;
      final subtitleColor = isCurrent
          ? theme.colorScheme.primary
          : (isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100));
      
      // Tile Content
      final Widget tile = AppListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: _multiSelect
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                  ),
                )
              : (showCovers
                  ? ArtworkWidget(
                      song: song,
                      size: 48,
                      borderRadius: 4,
                    )
                  : Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 16,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )),
        ),
        title: song.title,
        subtitle: song.artist,
        titleColor: titleColor,
        subtitleColor: subtitleColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        trailing: _multiSelect
            ? ReorderableDragStartListener(
                index: index,
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.menu, color: Colors.grey),
                ),
              )
            : null,
        onTap: () {
          if (_multiSelect) {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(song.id);
              } else {
                _selectedIds.add(song.id);
              }
            });
          } else {
            playerVM.playList(_songs, initialIndex: index);
          }
        },
        onLongPress: () {
          // Always show actions on long press, regardless of mode (though in multi-select, tap toggles)
          // User asked for "Long press opens song detail panel"
          SongDetailSheet.show(context, song);
        },
      );

      // Dismissible only in non-multi-select mode
      if (!_multiSelect) {
        return Dismissible(
          key: Key('playlist_${widget.playlist.id}_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('移除歌曲'),
                  content: const Text('确定要从歌单中移除这首歌曲吗？'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('移除'),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) {
            LibraryViewModel()
                .removeSongFromPlaylist(widget.playlist.id, song.id);
            setState(() {
              _songs.removeAt(index);
              _originalSongs.removeWhere((s) => s.id == song.id);
            });
          },
          child: tile,
        );
      } else {
        return tile;
      }
    }

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        bottomNavigationBar: null,
        appBar: AppBar(
        title: Text(widget.playlist.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                headerRow,
                Expanded(
                  child: _songs.isEmpty
                      ? const Center(child: Text('暂无歌曲'))
                      : canReorder
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              buildDefaultDragHandles: false, // Disable default long-press drag
                              itemCount: _songs.length,
                              proxyDecorator: (child, index, animation) {
                                return Material(
                                  color: Theme.of(context).cardColor.withValues(alpha: 0.8),
                                  elevation: 0,
                                  child: child,
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                if (oldIndex < newIndex) {
                                  newIndex -= 1;
                                }
                                final item = _songs.removeAt(oldIndex);
                                _songs.insert(newIndex, item);
                                
                                // Update DB and Original List
                                _originalSongs = List.from(_songs);
                                final ids = _songs.map((s) => s.id).toList();
                                LibraryViewModel().reorderPlaylist(widget.playlist.id, ids);
                                setState(() {});
                              },
                              itemBuilder: (context, index) {
                                return KeyedSubtree(
                                  key: ValueKey(_songs[index].id),
                                  child: buildListItem(index),
                                );
                              },
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: _songs.length,
                              itemBuilder: (context, index) {
                                return buildListItem(index);
                              },
                            ),
                ),
                // Bottom Bar for Multi-select Actions
                if (_multiSelect)
                  MultiSelectBottomBar(
                    actions: [
                      MultiSelectAction(
                        icon: Icons.queue_play_next,
                        label: '下一首播放',
                        onTap: _selectedIds.isEmpty ? null : () {
                          final selectedSongs = _songs.where((s) => _selectedIds.contains(s.id)).toList();
                          PlayerViewModel().insertNext(selectedSongs);
                          ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('已将 ${_selectedIds.length} 首歌曲加入下一首播放')),
                          );
                          setState(() {
                            _multiSelect = false;
                            _selectedIds.clear();
                          });
                          LibraryViewModel().setGlobalMultiSelectMode(false);
                        },
                      ),
                      MultiSelectAction(
                        icon: Icons.playlist_add,
                        label: '收藏到歌单',
                        onTap: _selectedIds.isEmpty ? null : () {
                          final selectedSongs = _songs.where((s) => _selectedIds.contains(s.id)).toList();
                          _showAddSongsToPlaylistDialog(selectedSongs);
                        },
                      ),
                      MultiSelectAction(
                        icon: Icons.delete_outline,
                        label: '移除',
                        isDestructive: true,
                        onTap: _selectedIds.isEmpty ? null : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) {
                              return AlertDialog(
                                title: const Text('移除选中歌曲'),
                                content: Text(
                                  '确定要从歌单中移除这 ${_selectedIds.length} 首歌曲吗？',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('确认移除'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (confirmed != true) return;
                          if (!context.mounted) return;

                          final ids = _selectedIds.toList();
                          final vm = LibraryViewModel();
                          for (final id in ids) {
                            await vm.removeSongFromPlaylist(
                              widget.playlist.id, id,);
                        }

                        if (!mounted) return;
                        setState(() {
                          _songs.removeWhere(
                              (s) => _selectedIds.contains(s.id),);
                          _originalSongs.removeWhere(
                              (s) => _selectedIds.contains(s.id),);
                          _selectedIds.clear();
                          _multiSelect = false; 
                        });
                          LibraryViewModel().setGlobalMultiSelectMode(false);
                        },
                      ),
                    ],
                  ),
              ],
            ),
    );
    },);
  }
}
