import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/storage/storage_keys.dart';
import '../../core/storage/storage_util.dart';
import '../../models/album_info.dart';
import '../../models/music_entity.dart';
import '../../utils/music_utils.dart';
import '../../viewmodels/library_viewmodel.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../widgets/alphabet_indexer.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_list_tile.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/artwork_widget.dart';
import '../../widgets/blocked_items_sheet.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/song_detail_sheet.dart';
import '../artists/artists_page.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  final ScrollController _scrollController = ScrollController();
  String? _indexPreviewLetter;
  bool _indexPreviewVisible = false;
  Timer? _indexPreviewTimer;

  // Sorting state
  late String _sortMode;
  late bool _sortAscending;
  late int _gridColumns;
  late bool _showBlockedEntry;

  @override
  void initState() {
    super.initState();
    _sortMode = StorageUtil.getStringOrDefault(StorageKeys.albumsSortKey, defaultValue: 'name');
    _sortAscending = StorageUtil.getBoolOrDefault(StorageKeys.albumsSortAscending, defaultValue: true);
    _gridColumns = StorageUtil.getInt(StorageKeys.albumsGridColumns) ?? 2;
    _showBlockedEntry = StorageUtil.getBoolOrDefault(StorageKeys.showBlockedAlbums, defaultValue: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _indexPreviewTimer?.cancel();
    super.dispose();
  }

  void _activateIndexPreview(String letter) {
    _indexPreviewTimer?.cancel();
    final changed = _indexPreviewLetter != letter;
    if (_indexPreviewVisible && !changed) return;
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

  void _showBlockedAlbums() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const BlockedAlbumsSheet();
      },
    );
  }

  void _showAlbumMenu(String albumName, Offset offset) {
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
          value: 'block',
          child: Row(
            children: [
              Icon(Icons.album_outlined, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Text('屏蔽专辑', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'block') {
        final vm = LibraryViewModel();
        vm.blockAlbum(albumName);
        if (!mounted) return;
        AppToast.show(context, '已屏蔽专辑: $albumName', type: ToastType.success);
      }
    });
  }

  void _scrollToIndex(int index, BuildContext context) {
    if (!_scrollController.hasClients) return;

    const listHeaderHeight = 72.0;

    if (_sortMode == 'year') {
      // ListView mode
      final offset = index * 72.0 + listHeaderHeight;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
      return;
    }
    
    final gridHeaderHeight = _showBlockedEntry ? 80.0 : 8.0;
    final screenWidth = MediaQuery.of(context).size.width;
    // Padding: 16 left, 16 right. Spacing: 16. 
    // Total horizontal deduction: 16 + 16 + (cols-1)*16.
    final totalSpacing = 16.0 * (_gridColumns - 1);
    final totalPadding = 16.0 + 16.0;
    final itemWidth = (screenWidth - totalPadding - totalSpacing) / _gridColumns;
    final aspectRatio = _gridColumns == 2
        ? 0.72
        : _gridColumns == 3
            ? 0.64
            : 0.56;
    final itemHeight = itemWidth / aspectRatio;
    final rowHeight = itemHeight + 16;
    
    final rowIndex = (index / _gridColumns).floor();
    final offset = rowIndex * rowHeight + gridHeaderHeight;
    
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(offset.clamp(0.0, max));
  }

  void _showSortSheet() {
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
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        String mode = _sortMode;
        bool asc = _sortAscending;
        int cols = _gridColumns;
        bool showBlocked = _showBlockedEntry;

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

        void applySort({String? nextMode, bool? nextAsc, int? nextCols, bool? nextShowBlocked}) {
          setState(() {
            if (nextMode != null) {
              _sortMode = nextMode;
              StorageUtil.setString(StorageKeys.albumsSortKey, nextMode);
            }
            if (nextAsc != null) {
              _sortAscending = nextAsc;
              StorageUtil.setBool(StorageKeys.albumsSortAscending, nextAsc);
            }
            if (nextCols != null) {
              _gridColumns = nextCols;
              StorageUtil.setInt(StorageKeys.albumsGridColumns, nextCols);
            }
            if (nextShowBlocked != null) {
              _showBlockedEntry = nextShowBlocked;
              StorageUtil.setBool(StorageKeys.showBlockedAlbums, nextShowBlocked);
            }
          });
        }

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setStateSheet) {
              return SingleChildScrollView(
                child: Column(
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
                  sectionTitle('专辑排序'),
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
                                  label: '名称',
                                  icon: Icons.sort_by_alpha,
                                  selected: mode == 'name',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextMode: 'name');
                                    mode = 'name';
                                  }),
                                ),
                                buildGridOption(
                                  label: '歌曲数',
                                  icon: Icons.music_note_outlined,
                                  selected: mode == 'count',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextMode: 'count');
                                    mode = 'count';
                                  }),
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '艺术家',
                                  icon: Icons.person_outline,
                                  selected: mode == 'artist',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextMode: 'artist');
                                    mode = 'artist';
                                  }),
                                ),
                                buildGridOption(
                                  label: '年份',
                                  icon: Icons.calendar_today_outlined,
                                  selected: mode == 'year',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextMode: 'year');
                                    mode = 'year';
                                  }),
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
                          (maxWidth - 56).clamp(0.0, maxWidth).toDouble();
                      return Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: contentWidth,
                          child: row(
                            buildGridOption(
                              label: '正序',
                              icon: Icons.arrow_downward,
                              selected: asc,
                              onTap: () => setStateSheet(() {
                                applySort(nextAsc: true);
                                asc = true;
                              }),
                            ),
                            buildGridOption(
                              label: '倒序',
                              icon: Icons.arrow_upward,
                              selected: !asc,
                              onTap: () => setStateSheet(() {
                                applySort(nextAsc: false);
                                asc = false;
                              }),
                              alignRight: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (mode != 'year') ...[
                    sectionTitle('显示布局'),
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
                              children: [
                                row(
                                  buildGridOption(
                                    label: '2列',
                                    icon: Icons.grid_view,
                                    selected: cols == 2,
                                    onTap: () => setStateSheet(() {
                                      applySort(nextCols: 2);
                                      cols = 2;
                                    }),
                                  ),
                                  buildGridOption(
                                    label: '3列',
                                    icon: Icons.grid_on,
                                    selected: cols == 3,
                                    onTap: () => setStateSheet(() {
                                      applySort(nextCols: 3);
                                      cols = 3;
                                    }),
                                    alignRight: true,
                                  ),
                                ),
                                row(
                                  buildGridOption(
                                    label: '4列',
                                    icon: Icons.grid_4x4,
                                    selected: cols == 4,
                                    onTap: () => setStateSheet(() {
                                      applySort(nextCols: 4);
                                      cols = 4;
                                    }),
                                  ),
                                  const SizedBox(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      '显示已屏蔽列表',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                    value: showBlocked,
                    activeTrackColor: primaryColor,
                    onChanged: (v) => setStateSheet(() {
                      applySort(nextShowBlocked: v);
                      showBlocked = v;
                    }),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 16,
                  ),
                ],
              ),
              );
            },
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
      final Map<String, AlbumInfo> albums = {};
      for (final song in vm.homeSongs) {
        final name = (song.album ?? '').trim().isEmpty ? '未知专辑' : song.album!.trim();
        final existing = albums[name];
        final artistLabel = primaryArtistLabel(song.artist);
        if (existing == null) {
          albums[name] = AlbumInfo(
            name: name,
            count: 1,
            artistLabel: artistLabel,
            representative: song,
          );
        } else {
          albums[name] = AlbumInfo(
            name: name,
            count: existing.count + 1,
            artistLabel: existing.artistLabel.isNotEmpty
                ? existing.artistLabel
                : artistLabel,
            representative: existing.representative,
          );
        }
      }
      final list = albums.values.toList()
        ..sort((a, b) {
          int result;
          switch (_sortMode) {
            case 'count':
              result = a.count.compareTo(b.count);
              break;
            case 'artist':
              final pinyinA = PinyinHelper.getPinyin(a.artistLabel, separator: '', format: PinyinFormat.WITHOUT_TONE).toLowerCase();
              final pinyinB = PinyinHelper.getPinyin(b.artistLabel, separator: '', format: PinyinFormat.WITHOUT_TONE).toLowerCase();
              result = pinyinA.compareTo(pinyinB);
              break;
            case 'year':
              final timeA = a.representative.fileModifiedMs ?? 0;
              final timeB = b.representative.fileModifiedMs ?? 0;
              result = timeA.compareTo(timeB);
              break;
            case 'name':
            default:
              final pinyinA = PinyinHelper.getPinyin(
                a.name,
                separator: '',
                format: PinyinFormat.WITHOUT_TONE,
              ).toLowerCase();
              final pinyinB = PinyinHelper.getPinyin(
                b.name,
                separator: '',
                format: PinyinFormat.WITHOUT_TONE,
              ).toLowerCase();
              result = pinyinA.compareTo(pinyinB);
              break;
          }
          return _sortAscending ? result : -result;
        });

      final blocked = vm.blockedAlbums;
      list.removeWhere((a) => blocked.contains(a.name));

      if (_sortMode == 'year') {
        final Map<int, List<AlbumInfo>> grouped = {};
        for (final album in list) {
          final date = album.representative.fileModifiedMs != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  album.representative.fileModifiedMs!,
                )
              : null;
          final year = date?.year ?? 0;
          if (!grouped.containsKey(year)) {
            grouped[year] = [];
          }
          grouped[year]!.add(album);
        }
        final sortedYears = grouped.keys.toList()
          ..sort((a, b) => _sortAscending ? a.compareTo(b) : b.compareTo(a));

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text('专辑'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: _showSortSheet,
              ),
            ],
          ),
          body: AppBackground(
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _showBlockedEntry ? sortedYears.length + 1 : sortedYears.length,
                    itemBuilder: (context, index) {
                        if (_showBlockedEntry && index == 0) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            elevation: 0,
                            color: Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const Icon(Icons.album_outlined, color: Colors.red),
                              title: const Text('已屏蔽的专辑'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _showBlockedAlbums,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                        final year = _showBlockedEntry ? sortedYears[index - 1] : sortedYears[index];
                        final albums = grouped[year]!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 4),
                              child: Text(
                                year == 0 ? '未知年份' : '$year',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: albums.length,
                              itemBuilder: (context, i) {
                                final album = albums[i];
                                return GestureDetector(
                                  onLongPressStart: (details) {
                                    _showAlbumMenu(album.name, details.globalPosition);
                                  },
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: ArtworkWidget(
                                      song: album.representative,
                                      size: 48,
                                      borderRadius: 8,
                                    ),
                                    title: SizedBox(
                                      height: 24,
                                      child: MarqueeText(
                                        album.name,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${album.count}首 · ${album.artistLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              AlbumDetailPage(albumName: album.name),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          bottomNavigationBar: null,
        );
      }

      final showIndexBar = _sortMode == 'name';
      final indexMap = <String, int>{};
      if (showIndexBar) {
        for (var i = 0; i < list.length; i++) {
          final name = list[i].name;
          final String letter;
          if (name == '未知专辑') {
            letter = '↑';
          } else {
            letter = IndexUtils.leadingLetter(name);
          }
          indexMap.putIfAbsent(letter, () => i);
        }
      }

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('专辑'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.sort),
              onPressed: _showSortSheet,
            ),
          ],
        ),
        body: AppBackground(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
              Expanded(
                child: Stack(
                  children: [
                    CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        if (_showBlockedEntry)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                elevation: 0,
                                color: Theme.of(context).cardColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: ListTile(
                                  leading: const Icon(Icons.album_outlined, color: Colors.red),
                                  title: const Text('已屏蔽的专辑'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: _showBlockedAlbums,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _gridColumns,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: _gridColumns == 2
                                  ? 0.72
                                  : _gridColumns == 3
                                      ? 0.64
                                      : 0.56,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final album = list[index];
                                final titleSize = _gridColumns == 2
                                    ? 14.0
                                    : _gridColumns == 3
                                        ? 13.0
                                        : 12.0;
                                final subtitleSize = _gridColumns == 2
                                    ? 12.0
                                    : _gridColumns == 3
                                        ? 11.0
                                        : 10.0;

                                return GestureDetector(
                                  onLongPressStart: (details) {
                                    _showAlbumMenu(album.name, details.globalPosition);
                                  },
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AlbumDetailPage(albumName: album.name),
                                        ),
                                      );
                                    },
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final coverSize = constraints.maxWidth;
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ArtworkWidget(
                                              song: album.representative,
                                              size: coverSize,
                                              borderRadius: 12,
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              height: 24,
                                              child: MarqueeText(
                                                album.name,
                                                style: TextStyle(
                                                  fontSize: titleSize,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${album.count}首 ${album.artistLabel}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: subtitleSize,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                    ?.withValues(alpha: 0.75),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                              childCount: list.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (list.isNotEmpty && showIndexBar)
                      Positioned(
                        right: 2,
                        top: 4,
                        bottom: 4,
                        child: DraggableScrollbar(
                    controller: _scrollController,
                    itemCount: list.length,
                    itemExtent: 0,
                    getLabel: (index) {
                      final name = list[index].name;
                      if (name == '未知专辑') return '↑';
                      return IndexUtils.leadingLetter(name);
                    },
                    onIndexChanged: (letter) {
                      _activateIndexPreview(letter);
                    },
                    onScrollRequest: (index) {
                      _scrollToIndex(index, context);
                    },
                    onDragEnd: () {
                      _scheduleHideIndexPreview();
                    },
                  ),
                ),
              if (showIndexBar)
                IndexPreview(
                  text: _indexPreviewLetter ?? '',
                  visible: _indexPreviewVisible,
                ),
            ],
          ),
        ),
          ],
        ),
      ),
      bottomNavigationBar: null,
        );
      },);
  }
}



class AlbumDetailPage extends StatefulWidget {
  final String albumName;

  const AlbumDetailPage({super.key, required this.albumName});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      final normalized = widget.albumName.trim();
      final songs = vm.homeSongs.where((song) {
      final raw = (song.album ?? '').trim();
      if (normalized == '未知专辑') {
        return raw.isEmpty;
      }
      return raw == normalized;
    }).toList();
    final representative = songs.isNotEmpty ? songs.first : null;
    final artistLabel =
        representative != null ? primaryArtistLabel(representative.artist) : '未知艺术家';
    final year = albumYearFromSongs(songs);
    final songCountText = '${songs.length}首';
    final infoText = year.isEmpty ? songCountText : '$songCountText · $year';
    final playerVM = PlayerViewModel();

    final Set<String> participatingArtists = {};
    for (final song in songs) {
      participatingArtists.addAll(splitArtists(song.artist));
    }
    final sortedArtists = participatingArtists.toList()
      ..sort(
        (a, b) =>
            PinyinHelper.getPinyin(a).compareTo(PinyinHelper.getPinyin(b)),
      );

      return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.albumName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: AppBackground(
        child: ListView(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (representative != null)
                  ArtworkWidget(
                    song: representative,
                    size: 110,
                    borderRadius: 12,
                  )
                else
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.albumName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artistLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        infoText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  '歌曲',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  tooltip: '随机播放',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (songs.isEmpty) return;
                    final shuffled = List<MusicEntity>.from(songs)..shuffle();
                    playerVM.playList(shuffled);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '顺序播放',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (songs.isEmpty) return;
                    playerVM.playList(songs);
                  },
                ),
              ],
            ),
          ),
          ...songs.asMap().entries.map((entry) {
            final index = entry.key;
            final song = entry.value;
            final isPlaying = playerVM.currentSong?.id == song.id;
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            
            final titleColor = isPlaying
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface;
            final subtitleColor = isPlaying
                ? theme.colorScheme.primary
                : (isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100));

            return AppListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              title: song.title,
              subtitle: song.artist,
              titleColor: titleColor,
              subtitleColor: subtitleColor,
              contentPadding: const EdgeInsets.only(left: 16, right: 16),
              onTap: () {
                playerVM.playList(songs, initialIndex: index);
              },
              onLongPress: () {
                SongDetailSheet.show(context, song);
              },
            );
          }),
          if (sortedArtists.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '参与创作的艺术家',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...sortedArtists.map((artist) {
              // Find a representative song for this artist to show artwork
              final artistSong = songs.firstWhere(
                (s) => splitArtists(s.artist).contains(artist),
                orElse: () => songs.first,
              );
              final initial = artist.isNotEmpty ? artist[0] : '?';
              
              return ListTile(
                leading: ArtworkWidget(
                  song: artistSong,
                  size: 44,
                  borderRadius: 22,
                  placeholder: CircleAvatar(
                    radius: 22,
                    child: Text(initial),
                  ),
                ),
                title: Text(artist),
                onTap: () {
                   Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistDetailPage(artistName: artist),
                    ),
                  );
                },
              );
            }),
          ],
          const SizedBox(height: 24),
        ],
      ),
      ),

    );
    },);
  }
}
