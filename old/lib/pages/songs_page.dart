import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../models/music_entity.dart';
import '../viewmodels/library_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/alphabet_indexer.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/multi_select_bottom_bar.dart';
import '../widgets/song_detail_sheet.dart';
import 'search_page.dart';


class SongsPage extends StatefulWidget {
  const SongsPage({super.key});
  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  bool _multiSelect = false;
  final Set<String> _selectedIds = {};
  final bool _searching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _lastPrefetchQuery = '';
  int _lastPrefetchCount = -1;
  final ScrollController _listController = ScrollController();
  static const double _songItemExtent = 64;
  bool _isSequentialPlay = false;
  String? _indexPreviewLetter;
  bool _indexPreviewVisible = false;
  Timer? _indexPreviewTimer;
  
  // Scraping state
  bool _isScraping = false;
  int _totalToScrape = 0;
  int _scrapedCount = 0;
  int _scrapedSuccess = 0;
  OverlayEntry? _scrapingOverlay;
  final LayerLink _scrapingLayerLink = LayerLink();

  @override
  void dispose() {
    // Reset global multi-select mode
    LibraryViewModel().setGlobalMultiSelectMode(false);
    _removeOverlay();
    _indexPreviewTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  void _removeOverlay() {
    _scrapingOverlay?.remove();
    _scrapingOverlay = null;
  }

  List<MusicEntity> _applySearch(List<MusicEntity> list) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return list;
    bool matches(String? value) =>
        value != null && value.toLowerCase().contains(q);
    return list.where((s) {
      return matches(s.title) ||
          matches(s.artist) ||
          matches(s.album) ||
          matches(s.lyrics);
    }).toList();
  }

  List<MusicEntity> _currentSongs(LibraryViewModel vm) {
    return _applySearch(vm.songs);
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_listController.hasClients) return;
    final offset = index * _songItemExtent;
    final max = _listController.position.maxScrollExtent;
    final target = offset.clamp(0.0, max);
    if (animate) {
      _listController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      _listController.jumpTo(target);
    }
  }

  void _activateIndexPreview(String letter) {
    _indexPreviewTimer?.cancel();
    final changed = _indexPreviewLetter != letter;
    if (_indexPreviewVisible && !changed) return;
    if (changed) {
      // Vibration removed as per user request
    }
    setState(() {
      _indexPreviewLetter = letter;
      _indexPreviewVisible = true;
    });
  }

  void _scheduleHideIndexPreview() {
    _indexPreviewTimer?.cancel();
    _indexPreviewTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _indexPreviewVisible = false;
      });
    });
  }

  // Implementation moved to alphabet_indexer.dart


  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    
    _scrapingOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _scrapingLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(-250, 45), // Position below the button, aligned right
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.blue,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '正在扫描',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          // Allow closing the overlay but keep scraping in background?
                          // Or just hide overlay. The scraping loop continues.
                          _removeOverlay();
                        },
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已找到 $_totalToScrape，待更新 ${_totalToScrape - _scrapedCount}，已更新 $_scrapedSuccess',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _totalToScrape > 0 ? _scrapedCount / _totalToScrape : 0,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_scrapingOverlay!);
  }

  void _updateOverlay() {
    _scrapingOverlay?.markNeedsBuild();
  }


  Future<void> _showAddSongsToPlaylistDialog(List<MusicEntity> songs) async {
    final vm = LibraryViewModel();
    // Ensure playlists are loaded (though they should be)
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


  void _showSortSheet(LibraryViewModel vm) {
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
        String key = vm.sortKey;
        bool asc = vm.ascending;
        Widget buildGridOption({
          required String label,
          required IconData icon,
          required bool selected,
          required VoidCallback onTap,
          bool alignRight = false,
        }) {
          final color = selected ? primaryColor : secondaryTextColor;
          final bgColor = selected
              ? primaryColor.withValues(alpha: isDark ? 0.18 : 0.12)
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
            padding: const EdgeInsets.only(bottom: 12),
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

        final libraryVM = LibraryViewModel();
        void applySort({String? nextKey, bool? nextAsc}) {
          key = nextKey ?? key;
          asc = nextAsc ?? asc;
          libraryVM.setSort(key: key, ascending: asc);
        }

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setStateSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: secondaryTextColor.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  sectionTitle('歌曲排序'),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final contentWidth =
                          (maxWidth - 56).clamp(0.0, maxWidth).toDouble();
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
                                  selected: key == 'title',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'title');
                                  }),
                                ),
                                buildGridOption(
                                  label: '专辑名称',
                                  icon: Icons.album_outlined,
                                  selected: key == 'album',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'album');
                                  }),
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '歌手名称',
                                  icon: Icons.person_outline,
                                  selected: key == 'artist',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'artist');
                                  }),
                                ),
                                buildGridOption(
                                  label: '歌曲时长',
                                  icon: Icons.schedule,
                                  selected: key == 'duration',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'duration');
                                  }),
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '文件大小',
                                  icon: Icons.insert_drive_file_outlined,
                                  selected: key == 'fileSize',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'fileSize');
                                  }),
                                ),
                                buildGridOption(
                                  label: '最近添加',
                                  icon: Icons.history,
                                  selected: key == 'recentAdded',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'recentAdded');
                                  }),
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '最近修改',
                                  icon: Icons.update,
                                  selected: key == 'recentModified',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'recentModified');
                                  }),
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
                                selected: asc,
                                onTap: () => setStateSheet(() {
                                  applySort(nextAsc: true);
                                }),
                              ),
                              buildGridOption(
                                label: '降序',
                                icon: Icons.arrow_downward,
                                selected: !asc,
                                onTap: () => setStateSheet(() {
                                  applySort(nextAsc: false);
                                }),
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
              );
            },
          ),
        );
      },
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

  Future<void> _startScraping() async {
    final vm = LibraryViewModel();
    final playerVM = PlayerViewModel();

    if (_isScraping) {
       _showOverlay(); // Bring back overlay if already scraping
       return;
    }

    final visible = _currentSongs(vm);
    final songs = _multiSelect && _selectedIds.isNotEmpty
        ? visible.where((s) => _selectedIds.contains(s.id)).toList()
        : visible;

    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('列表为空')),
      );
      return;
    }

    setState(() {
      _isScraping = true;
      _totalToScrape = songs.length;
      _scrapedCount = 0;
      _scrapedSuccess = 0;
    });

    _showOverlay();

    for (final song in songs) {
      if (!mounted) break;
      // If user closed overlay, we still continue? Yes.
      // But if user left page, dispose is called and overlay removed.
      
      final success = await playerVM.fetchRemoteEmbeddedTags(song);
      
      if (!mounted) break;
      setState(() {
        _scrapedCount++;
        if (success) _scrapedSuccess++;
      });
      _updateOverlay();
    }

    if (mounted) {
      setState(() {
        _isScraping = false;
      });
      // Delay closing overlay slightly to show 100%
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _removeOverlay();
    }
  }

  String _getFilterLabel(SongFilter filter) {
    switch (filter) {
      case SongFilter.all:
        return '全部';
      case SongFilter.local:
        return '本地';
      case SongFilter.webdav:
        return '云端';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      watchSignal(context, vm.scanTick);
      final playerVM = PlayerViewModel();
      watchSignal(context, playerVM.queueTick);
      watchSignal(context, playerVM.playbackTick);
      watchSignal(context, playerVM.lyricsTick);
      final visibleSongs = _currentSongs(vm);
    if (_lastPrefetchQuery != _searchQuery ||
        _lastPrefetchCount != visibleSongs.length) {
      _lastPrefetchQuery = _searchQuery;
      _lastPrefetchCount = visibleSongs.length;
      if (visibleSongs.isNotEmpty) {
        // Limit prefetching to first 500 items to avoid excessive resource usage
        Future.microtask(() => ArtworkWidget.prefetchAll(visibleSongs.take(500).toList()));
      }
    }
    final totalCount = visibleSongs.length;
    final selectedCount = _selectedIds.length;
    final isAllSelected = totalCount > 0 && selectedCount == totalCount;

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
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () {
            final val = LibraryViewModel().isMenuOpen.value;
            LibraryViewModel().isMenuOpen.value = !val;
          },
        ),
        title: _searching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  LibraryViewModel().enqueueLocalSearchMetadata(_searchQuery);
                },
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索 歌名/歌手/专辑/歌词',
                  border: InputBorder.none,
                ),
              )
            : PopupMenuButton<SongFilter>(
                initialValue: vm.filter,
                onSelected: (SongFilter item) {
                  vm.setFilter(item);
                },
                position: PopupMenuPosition.under,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_getFilterLabel(vm.filter)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<SongFilter>>[
                  const PopupMenuItem<SongFilter>(
                    value: SongFilter.all,
                    child: Text('全部'),
                  ),
                  const PopupMenuItem<SongFilter>(
                    value: SongFilter.local,
                    child: Text('本地'),
                  ),
                  const PopupMenuItem<SongFilter>(
                    value: SongFilter.webdav,
                    child: Text('云端'),
                  ),
                ],
              ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              );
            },
          ),
          CompositedTransformTarget(
            link: _scrapingLayerLink,
            child: IconButton(
              icon: _isScraping 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.label_important_outline),
              tooltip: '读取内置标签',
              onPressed: _startScraping,
            ),
          ),
        ],
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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                    child: Row(
                      children: [
                        _multiSelect
                            ? InkWell(
                                onTap: () {
                                  if (visibleSongs.isEmpty) return;
                                  setState(() {
                                    if (isAllSelected) {
                                      _selectedIds.clear();
                                    } else {
                                      _selectedIds
                                        ..clear()
                                        ..addAll(visibleSongs.map((e) => e.id));
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
                                  final list = visibleSongs;
                                  if (list.isNotEmpty) {
                                    if (_isSequentialPlay) {
                                      PlayerViewModel().playList(list);
                                    } else {
                                      final shuffled = List<MusicEntity>.from(list)..shuffle();
                                      PlayerViewModel().playList(shuffled);
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
                                    Icon(_isSequentialPlay ? Icons.playlist_play : Icons.shuffle, size: 20),
                                    const SizedBox(width: 4),
                                    Text('${_isSequentialPlay ? '顺序播放' : '随机播放'} ($totalCount)'),
                                  ],
                                ),
                              ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.sort),
                          onPressed: () async {
                            _showSortSheet(vm);
                          },
                        ),
                        IconButton(
                          icon: Icon(_multiSelect ? Icons.checklist : Icons.checklist_rtl),
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
                  ),
                  Expanded(
                    child: vm.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : visibleSongs.isEmpty
                            ? Center(
                                child: Text(
                                  _searchQuery.trim().isEmpty
                                      ? '暂无歌曲，请去音源配置'
                                      : '没有匹配的歌曲',
                                ),
                              )
                            : Stack(
                                children: [
                                  ListView.builder(
                                    controller: _listController,
                                    itemExtent: _songItemExtent,
                                    // Reduced padding to allow more space for content
                                    padding: const EdgeInsets.only(right: 4, bottom: 160),
                                    itemCount: visibleSongs.length,
                                    itemBuilder: (context, index) {
                                      final s = visibleSongs[index];
                                      // Get current song from player view model
                                      final isPlaying = playerVM.currentSong?.id == s.id;
                                      return _SongTile(
                                        song: s,
                                        selected: _selectedIds.contains(s.id),
                                        isPlaying: isPlaying,
                                        multiSelect: _multiSelect,
                                        onTap: () {
                                            if (_multiSelect) {
                                              setState(() {
                                                if (_selectedIds.contains(s.id)) {
                                                  _selectedIds.remove(s.id);
                                                } else {
                                                  _selectedIds.add(s.id);
                                                }
                                              });
                                            } else if (s.uri != null) {
                                              PlayerViewModel().playList(
                                                visibleSongs,
                                                initialIndex: index,
                                              );
                                            }
                                          },
                                          onLongPress: () {
                                            SongDetailSheet.show(context, s);
                                          },
                                        );
                                      },
                                    ),
                                  Positioned(
                                    right: 36,
                                    top: 0,
                                    bottom: 0,
                                    child: IgnorePointer(
                                      child: AnimatedOpacity(
                                        opacity: _indexPreviewVisible &&
                                                _indexPreviewLetter != null
                                            ? 1
                                            : 0,
                                        duration: const Duration(milliseconds: 120),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: _indexPreviewLetter == null
                                              ? const SizedBox.shrink()
                                              : Container(
                                                  width: 56,
                                                  height: 56,
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0.9),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Center(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        _indexPreviewLetter!,
                                                        style: TextStyle(
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onPrimary,
                                                          fontSize: 26,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 2,
                                    top: 4,
                                    bottom: 4,
                                    child: DraggableScrollbar(
                                      controller: _listController,
                                      itemCount: visibleSongs.length,
                                      itemExtent: _songItemExtent,
                                      getLabel: (index) => IndexUtils.leadingLetter(visibleSongs[index].title),
                                      onIndexChanged: (letter) {
                                        _activateIndexPreview(letter);
                                      },
                                      onDragEnd: () {
                                        _scheduleHideIndexPreview();
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    right: 24,
                                    bottom: MediaQuery.of(context).padding.bottom +
                                        (_multiSelect ? 88 : 160),
                                    child: Builder(
                                      builder: (context) {
                                        final currentSong = playerVM.currentSong;
                                        if (currentSong == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return FloatingActionButton(
                                          mini: true,
                                          backgroundColor: Theme.of(context)
                                              .scaffoldBackgroundColor,
                                          foregroundColor:
                                              Theme.of(context).colorScheme.onSurface,
                                          onPressed: () {
                                            final index = visibleSongs.indexWhere(
                                              (s) => s.id == currentSong.id,
                                            );
                                            if (index == -1) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('当前播放歌曲不在列表中'),
                                                ),
                                              );
                                              return;
                                            }
                                            _scrollToIndex(index);
                                          },
                                          child: const Icon(
                                            Icons.my_location,
                                            size: 18,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                  ),
                  if (_multiSelect)
                    MultiSelectBottomBar(
                      actions: [
                        MultiSelectAction(
                          icon: Icons.queue_play_next,
                          label: '下一首播放',
                          onTap: selectedCount == 0 ? null : () {
                            final vm = LibraryViewModel();
                            final selectedSongs = vm.songs.where((s) => _selectedIds.contains(s.id)).toList();
                            PlayerViewModel().insertNext(selectedSongs);
                            ScaffoldMessenger.of(context).showSnackBar(
                               SnackBar(content: Text('已将 $selectedCount 首歌曲加入下一首播放')),
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
                          onTap: selectedCount == 0 ? null : () {
                            final vm = LibraryViewModel();
                            final selectedSongs = vm.songs.where((s) => _selectedIds.contains(s.id)).toList();
                            _showAddSongsToPlaylistDialog(selectedSongs);
                          },
                        ),
                        MultiSelectAction(
                          icon: Icons.delete_outline,
                          label: '删除',
                          isDestructive: true,
                          onTap: selectedCount == 0 ? null : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) {
                                return AlertDialog(
                                  title: const Text('确认移除曲目'),
                                  content: const Text(
                                    '只会从曲库中移除记录，不会删除实际文件，重新扫描可恢复。',
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
                            final ids = _selectedIds.toList();
                            if (!context.mounted) return;
                            await LibraryViewModel().removeSongsByIds(ids);
                            if (!mounted) return;
                            setState(() {
                              _selectedIds.clear();
                            });
                          },
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
    },);
  }


}

class _SongTile extends StatelessWidget {
  final MusicEntity song;
  final bool selected;
  final bool isPlaying;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _SongTile({
    required this.song,
    required this.selected,
    this.isPlaying = false,
    required this.multiSelect,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = isPlaying
        ? theme.colorScheme.primary
        : (isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100));
    final titleColor = isPlaying
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final artist = song.artist.trim();
    final album = (song.album ?? '').trim();
    final subtitle = album.isEmpty ? artist : '$artist · $album';
    return AppListTile(
      leading: multiSelect
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                ),
                const SizedBox(width: 12),
                ArtworkWidget(
                  song: song,
                  size: 48,
                  borderRadius: 6,
                ),
              ],
            )
          : ArtworkWidget(
              song: song,
              size: 48,
              borderRadius: 6,
            ),
      title: song.title,
      subtitle: subtitle,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      trailing: null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
