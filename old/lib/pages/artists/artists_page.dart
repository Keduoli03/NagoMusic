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
import '../../widgets/app_toast.dart';
import '../../widgets/artwork_widget.dart';
import '../../widgets/blocked_items_sheet.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/song_detail_sheet.dart';
import '../albums/albums_page.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  late String _sortKey;
  late bool _ascending;
  late bool _filterUnknown;
  late bool _showBlockedEntry;
  final ScrollController _scrollController = ScrollController();
  static const double _itemExtent = 72.0;
  String? _indexPreviewLetter;
  bool _indexPreviewVisible = false;
  Timer? _indexPreviewTimer;

  @override
  void initState() {
    super.initState();
    _sortKey = StorageUtil.getStringOrDefault(StorageKeys.artistsSortKey, defaultValue: 'name');
    _ascending = StorageUtil.getBoolOrDefault(StorageKeys.artistsSortAscending, defaultValue: true);
    _filterUnknown = StorageUtil.getBoolOrDefault(StorageKeys.artistsFilterUnknown, defaultValue: false);
    _showBlockedEntry = StorageUtil.getBoolOrDefault(StorageKeys.showBlockedArtists, defaultValue: true);
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

  void _showBlockedArtists() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return const BlockedArtistsSheet();
      },
    );
  }

  void _showArtistMenu(String artistName, Offset offset) {
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
              Icon(Icons.person_off, size: 20, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Text('屏蔽艺术家', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'block') {
        final vm = LibraryViewModel();
        vm.blockArtist(artistName);
        if (!mounted) return;
        AppToast.show(context, '已屏蔽艺术家: $artistName', type: ToastType.success);
      }
    });
  }

  void _showSortSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.scaffoldBackgroundColor;
    final secondaryTextColor = theme.hintColor;
    final primaryColor = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String key = _sortKey;
        bool asc = _ascending;
        bool filterUnknown = _filterUnknown;
        bool showBlocked = _showBlockedEntry;

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
                children: [left, right],
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

        void applySort({String? nextKey, bool? nextAsc, bool? nextFilter, bool? nextShowBlocked}) {
          setState(() {
            if (nextKey != null) {
              _sortKey = nextKey;
              StorageUtil.setString(StorageKeys.artistsSortKey, nextKey);
            }
            if (nextAsc != null) {
              _ascending = nextAsc;
              StorageUtil.setBool(StorageKeys.artistsSortAscending, nextAsc);
            }
            if (nextFilter != null) {
              _filterUnknown = nextFilter;
              StorageUtil.setBool(StorageKeys.artistsFilterUnknown, nextFilter);
            }
            if (nextShowBlocked != null) {
              _showBlockedEntry = nextShowBlocked;
              StorageUtil.setBool(StorageKeys.showBlockedArtists, nextShowBlocked);
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
                  sectionTitle('艺术家排序'),
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
                                  label: '艺术家名',
                                  icon: Icons.person_outline,
                                  selected: key == 'name',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'name');
                                    key = 'name';
                                  }),
                                ),
                                buildGridOption(
                                  label: '歌曲数',
                                  icon: Icons.music_note_outlined,
                                  selected: key == 'songCount',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'songCount');
                                    key = 'songCount';
                                  }),
                                  alignRight: true,
                                ),
                              ),
                              row(
                                buildGridOption(
                                  label: '专辑数',
                                  icon: Icons.album_outlined,
                                  selected: key == 'albumCount',
                                  onTap: () => setStateSheet(() {
                                    applySort(nextKey: 'albumCount');
                                    key = 'albumCount';
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
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      '过滤未知艺术家',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                    value: filterUnknown,
                    activeTrackColor: primaryColor,
                    onChanged: (v) => setStateSheet(() {
                      applySort(nextFilter: v);
                      filterUnknown = v;
                    }),
                  ),
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
      final Map<String, _ArtistInfo> artists = {};
      for (final song in vm.homeSongs) {
        final rawNames = splitArtists(song.artist);
        final names = rawNames.where((n) {
          final lower = n.toLowerCase();
          return lower != '<unknown>' &&
              lower != 'unknown' &&
              lower != 'unknown artist' &&
              lower != '?';
        }).toList();

        if (names.isEmpty) {
          // Unknown artist
          final name = '未知艺术家';
          final existing = artists[name];
          final albumName = (song.album ?? '').trim();
          if (existing == null) {
            artists[name] = _ArtistInfo(
              name: name,
              songCount: 1,
              albumNames: {albumName},
              representative: song,
            );
          } else {
            artists[name] = _ArtistInfo(
              name: name,
              songCount: existing.songCount + 1,
              albumNames: {...existing.albumNames, albumName},
              representative: existing.representative,
            );
          }
        } else {
          for (final name in names) {
            final existing = artists[name];
            final albumName = (song.album ?? '').trim();
            if (existing == null) {
              artists[name] = _ArtistInfo(
                name: name,
                songCount: 1,
                albumNames: {albumName},
                representative: song,
              );
            } else {
              artists[name] = _ArtistInfo(
                name: name,
                songCount: existing.songCount + 1,
                albumNames: {...existing.albumNames, albumName},
                representative: existing.representative,
              );
            }
          }
        }
      }
      final entries = artists.values.toList();
      // Filter blocked
      final blocked = vm.blockedArtists;
      entries.removeWhere((e) => blocked.contains(e.name));

      if (_filterUnknown) {
        entries.removeWhere((e) => e.name == '未知艺术家');
      }

      if (_sortKey == 'name') {
        entries.sort((a, b) {
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
          return pinyinA.compareTo(pinyinB);
        });
      } else if (_sortKey == 'songCount') {
        entries.sort((a, b) => a.songCount.compareTo(b.songCount));
      } else if (_sortKey == 'albumCount') {
        entries.sort((a, b) => a.albumCount.compareTo(b.albumCount));
      }

      if (!_ascending) {
        final reversed = entries.reversed.toList();
        entries.clear();
        entries.addAll(reversed);
      }

      if (!_filterUnknown) {
        final unknownIndex = entries.indexWhere((e) => e.name == '未知艺术家');
        if (unknownIndex != -1) {
          final unknown = entries.removeAt(unknownIndex);
          entries.insert(0, unknown);
        }
      }

      final indexMap = <String, int>{};
      for (var i = 0; i < entries.length; i++) {
        final name = entries[i].name;
        final String letter;
        if (name == '未知艺术家') {
          letter = '↑';
        } else {
          letter = IndexUtils.leadingLetter(name);
        }
        indexMap.putIfAbsent(letter, () => i);
      }

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('艺术家'),
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
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 16, bottom: 80),
                      itemExtent: _itemExtent,
                      itemCount: _showBlockedEntry ? entries.length + 1 : entries.length,
                      itemBuilder: (context, index) {
                        if (_showBlockedEntry && index == 0) {
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: 0,
                            color: Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const Icon(Icons.person_off, color: Colors.red),
                              title: const Text('已屏蔽的艺术家'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _showBlockedArtists,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                        final e = _showBlockedEntry ? entries[index - 1] : entries[index];
                        final initial = e.name.isNotEmpty ? e.name.characters.first : '?';
                        return GestureDetector(
                          onLongPressStart: (details) {
                            _showArtistMenu(e.name, details.globalPosition);
                          },
                          child: ListTile(
                            leading: ArtworkWidget(
                              song: e.representative,
                              size: 44,
                              borderRadius: 22,
                              placeholder: CircleAvatar(
                                radius: 22,
                                child: Text(initial),
                              ),
                            ),
                            title: Text(e.name),
                            subtitle: Text('专辑：${e.albumCount}  歌曲：${e.songCount}'),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ArtistDetailPage(artistName: e.name),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    if (entries.isNotEmpty)
                      Positioned(
                        right: 2,
                        top: 4,
                        bottom: 4,
                        child: DraggableScrollbar(
                          controller: _scrollController,
                          itemCount: _showBlockedEntry ? entries.length + 1 : entries.length,
                          itemExtent: _itemExtent,
                          getLabel: (index) {
                             if (_showBlockedEntry) {
                               if (index == 0) return '';
                               if (index - 1 >= entries.length) return '';
                               final name = entries[index - 1].name;
                               if (name == '未知艺术家') return '↑';
                               return IndexUtils.leadingLetter(name);
                             } else {
                               if (index >= entries.length) return '';
                               final name = entries[index].name;
                               if (name == '未知艺术家') return '↑';
                               return IndexUtils.leadingLetter(name);
                             }
                          },
                          onIndexChanged: (letter) {
                            _activateIndexPreview(letter);
                          },
                          onDragEnd: () {
                            _scheduleHideIndexPreview();
                          },
                        ),
                      ),
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

class _ArtistInfo {
  final String name;
  final int songCount;
  final Set<String> albumNames;
  final MusicEntity representative;

  const _ArtistInfo({
    required this.name,
    required this.songCount,
    required this.albumNames,
    required this.representative,
  });

  int get albumCount => albumNames.length;
}

class ArtistDetailPage extends StatefulWidget {
  final String artistName;

  const ArtistDetailPage({super.key, required this.artistName});

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  bool _isAlbumsExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      final normalized = widget.artistName.trim();
      final songs = vm.homeSongs.where((song) {
      final rawNames = splitArtists(song.artist);
      final names = rawNames.where((n) {
        final lower = n.toLowerCase();
        return lower != '<unknown>' &&
            lower != 'unknown' &&
            lower != 'unknown artist' &&
            lower != '?';
      }).toList();
      if (normalized == '未知艺术家') {
        return names.isEmpty || names.contains('未知艺术家');
      }
      return names.contains(normalized);
    }).toList();

    final Map<String, AlbumInfo> albums = {};
    for (final song in songs) {
      final name =
          (song.album ?? '').trim().isEmpty ? '未知专辑' : song.album!.trim();
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
    final albumList = albums.values.toList()
      ..sort((a, b) {
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
        return pinyinA.compareTo(pinyinB);
      });

    final theme = Theme.of(context);
    final secondaryTextColor = theme.brightness == Brightness.dark
        ? Colors.white70
        : Colors.black54;

      return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.artistName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: AppBackground(
        child: ListView(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 16, bottom: 8),
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (songs.isNotEmpty)
                  ArtworkWidget(
                    song: songs.first,
                    size: 80,
                    borderRadius: 40,
                  )
                else
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.artistName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${songs.length} 首歌  •  ${albumList.length} 张专辑',
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Albums Section
          if (albumList.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    '专辑',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _isAlbumsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    onPressed: () {
                      setState(() {
                        _isAlbumsExpanded = !_isAlbumsExpanded;
                      });
                    },
                    tooltip: _isAlbumsExpanded ? '收起专辑' : '展开专辑',
                  ),
                ],
              ),
            ),
            if (_isAlbumsExpanded)
              ...albumList.map((album) {
                return ListTile(
                  leading: ArtworkWidget(
                    song: album.representative,
                    size: 48,
                    borderRadius: 8,
                  ),
                  title: SizedBox(
                    height: 24,
                    child: MarqueeText(
                      album.name,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  subtitle: Text('${album.count} 首歌曲'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AlbumDetailPage(albumName: album.name),
                      ),
                    );
                  },
                );
              }),
          ],

          // Songs Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text(
                  '歌曲',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  tooltip: '随机播放',
                  onPressed: () {
                    if (songs.isEmpty) return;
                    final playerVM = PlayerViewModel();
                    final shuffled = List<MusicEntity>.from(songs)..shuffle();
                    playerVM.playList(shuffled);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '顺序播放',
                  onPressed: () {
                    if (songs.isEmpty) return;
                    PlayerViewModel().playList(songs);
                  },
                ),
              ],
            ),
          ),
          ...songs.map((song) {
            final albumName = (song.album ?? '').trim().isEmpty
                ? '未知专辑'
                : song.album!.trim();
            return ListTile(
              leading: ArtworkWidget(
                song: song,
                size: 48,
                borderRadius: 6,
              ),
              title: SizedBox(
                height: 24,
                child: MarqueeText(
                  song.title,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              subtitle: SizedBox(
                height: 20,
                child: MarqueeText(
                  albumName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ),
              onTap: () {
                final playerVM = PlayerViewModel();
                // Play starting from this song in the current list
                final index = songs.indexOf(song);
                playerVM.playList(songs, initialIndex: index);
              },
              onLongPress: () {
                SongDetailSheet.show(context, song);
              },
            );
          }),
        ],
      ),
      ),

    );
    },);
  }
}
