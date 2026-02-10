import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/db/dao/song_dao.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import 'library_detail_pages.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumGroup {
  final String name;
  final int songCount;
  final SongEntity representative;

  const _AlbumGroup({
    required this.name,
    required this.songCount,
    required this.representative,
  });
}

class _AlbumsPageState extends State<AlbumsPage> with SignalsMixin {
  static const String _prefsSortMode = 'albums_sort_mode_v1';
  static const String _prefsSortAscending = 'albums_sort_ascending_v1';
  static const String _prefsGridColumns = 'albums_grid_columns_v1';
  static const String _prefsShowBlockedEntry = 'albums_show_blocked_entry_v1';
  static const String _prefsBlockedAlbums = 'blocked_albums_v1';

  final SongDao _songDao = SongDao();
  final ScrollController _controller = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final _loading = createSignal(true);
  late final _groups = createSignal<List<_AlbumGroup>>([]);
  late final _sortMode = createSignal('name');
  late final _ascending = createSignal(true);
  late final _gridColumns = createSignal(2);
  late final _showBlockedEntry = createSignal(true);
  late final _blockedAlbums = createSignal<Set<String>>({});

  late final _indexPreviewLetter = createSignal<String?>(null);
  late final _indexPreviewVisible = createSignal(false);
  Timer? _indexPreviewTimer;

  double _gridAspectRatioForColumns(int cols) {
    if (cols == 2) return 0.76;
    if (cols == 3) return 0.65;
    return 0.57;
  }

  double _gridMainAxisSpacingForColumns(int cols) {
    return 12.0;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _indexPreviewTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadPrefs();
    await _load();
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _activateIndexPreview(String letter) {
    _indexPreviewTimer?.cancel();
    final changed = _indexPreviewLetter.value != letter;
    if (_indexPreviewVisible.value && !changed) return;
    _indexPreviewLetter.value = letter;
    _indexPreviewVisible.value = true;
  }

  void _scheduleHideIndexPreview() {
    _indexPreviewTimer?.cancel();
    _indexPreviewTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _indexPreviewVisible.value = false;
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var mode = (prefs.getString(_prefsSortMode) ?? 'name').trim();
    if (mode.isEmpty) mode = 'name';
    var asc = prefs.getBool(_prefsSortAscending) ?? true;
    var cols = prefs.getInt(_prefsGridColumns) ?? 2;
    if (cols < 2) cols = 2;
    if (cols > 4) cols = 4;
    final showBlocked = prefs.getBool(_prefsShowBlockedEntry) ?? true;
    final blocked = prefs.getStringList(_prefsBlockedAlbums) ?? const <String>[];
    _sortMode.value = mode;
    _ascending.value = asc;
    _gridColumns.value = cols;
    _showBlockedEntry.value = showBlocked;
    _blockedAlbums.value =
        blocked.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSortMode, _sortMode.value);
    await prefs.setBool(_prefsSortAscending, _ascending.value);
    await prefs.setInt(_prefsGridColumns, _gridColumns.value);
    await prefs.setBool(_prefsShowBlockedEntry, _showBlockedEntry.value);
    await prefs.setStringList(
        _prefsBlockedAlbums, _blockedAlbums.value.toList()..sort());
  }

  Future<void> _load() async {
    _loading.value = true;
    final songs = await _songDao.fetchAll();
    final groups = await compute(
      _buildAlbumGroups,
      {
        'songs': songs.map((e) => e.toMap()).toList(),
        'blocked': _blockedAlbums.value.toList(),
        'sortMode': _sortMode.value,
        'ascending': _ascending.value,
      },
    );

    if (!mounted) return;
    _groups.value = groups
        .map(
          (e) => _AlbumGroup(
            name: e['name'] as String,
            songCount: e['songCount'] as int,
            representative: SongEntity.fromMap(
              (e['representative'] as Map).cast<String, dynamic>(),
            ),
          ),
        )
        .toList();
    _loading.value = false;
  }

  void _sortGroups(List<_AlbumGroup> groups) {
    int yearOf(_AlbumGroup g) {
      final ms = g.representative.fileModifiedMs;
      if (ms == null || ms <= 0) return 0;
      return DateTime.fromMillisecondsSinceEpoch(ms).year;
    }

    int compare(_AlbumGroup a, _AlbumGroup b) {
      if (_sortMode.value == 'songCount') {
        return a.songCount.compareTo(b.songCount);
      }
      if (_sortMode.value == 'artist') {
        final aa = primaryArtistLabel(a.representative.artist);
        final bb = primaryArtistLabel(b.representative.artist);
        return pinyinKey(aa).compareTo(pinyinKey(bb));
      }
      if (_sortMode.value == 'year') {
        return yearOf(a).compareTo(yearOf(b));
      }
      return pinyinKey(a.name).compareTo(pinyinKey(b.name));
    }

    groups.sort(compare);
    if (!_ascending.value) {
      groups.replaceRange(0, groups.length, groups.reversed);
    }
    if (_sortMode.value != 'year') {
      final idx = groups.indexWhere((g) => g.name == '未知专辑');
      if (idx >= 0) {
        final unknown = groups.removeAt(idx);
        groups.insert(0, unknown);
      }
    }
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        var nextMode = _sortMode.value;
        var nextAsc = _ascending.value;
        var nextCols = _gridColumns.value;
        var nextShowBlockedEntry = _showBlockedEntry.value;

        void apply() {
          _sortMode.value = nextMode;
          _ascending.value = nextAsc;
          _gridColumns.value = nextCols;
          _showBlockedEntry.value = nextShowBlockedEntry;
          final groups = _groups.value.toList();
          _sortGroups(groups);
          _groups.value = groups;
          _savePrefs();
        }

        Widget optionRow({
          required String label,
          required String mode,
          required IconData icon,
        }) {
          final selected = nextMode == mode;
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: selected ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              nextMode = mode;
              apply();
            },
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.62,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              snap: true,
              builder: (context, scrollController) {
                return StatefulBuilder(
                  builder: (context, setInner) {
                    void update(void Function() fn) {
                      setInner(fn);
                      apply();
                    }

                    return AppSheetPanel(
                      title: '排序',
                      expand: true,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            optionRow(
                              label: '名称',
                              mode: 'name',
                              icon: Icons.sort_by_alpha,
                            ),
                            optionRow(
                              label: '歌曲数',
                              mode: 'songCount',
                              icon: Icons.music_note_outlined,
                            ),
                            optionRow(
                              label: '艺术家',
                              mode: 'artist',
                              icon: Icons.person_outline,
                            ),
                            optionRow(
                              label: '年份',
                              mode: 'year',
                              icon: Icons.calendar_today_outlined,
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              title: const Text('升序'),
                              value: nextAsc,
                              onChanged: (v) => update(() => nextAsc = v),
                            ),
                            SwitchListTile(
                              title: const Text('显示已屏蔽入口'),
                              value: nextShowBlockedEntry,
                              onChanged: (v) =>
                                  update(() => nextShowBlockedEntry = v),
                            ),
                            if (nextMode != 'year')
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: SegmentedButton<int>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 2,
                                        label: Text('二列'),
                                        icon: Icon(Icons.grid_view_rounded),
                                      ),
                                      ButtonSegment(
                                        value: 3,
                                        label: Text('三列'),
                                        icon: Icon(Icons.grid_view_rounded),
                                      ),
                                      ButtonSegment(
                                        value: 4,
                                        label: Text('四列'),
                                        icon: Icon(Icons.grid_view_rounded),
                                      ),
                                    ],
                                    selected: {nextCols},
                                    onSelectionChanged: (selection) {
                                      final v = selection.first;
                                      update(() => nextCols = v);
                                    },
                                    showSelectedIcon: false,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _blockAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _blockedAlbums.value = {..._blockedAlbums.value, trimmed};
    await _savePrefs();
    if (!mounted) return;
    AppToast.show(context, '已屏蔽专辑: $trimmed', type: ToastType.success);
    await _load();
  }

  Future<void> _unblockAlbum(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = _blockedAlbums.value.toSet();
    next.remove(trimmed);
    _blockedAlbums.value = next;
    await _savePrefs();
    if (!mounted) return;
    await _load();
  }

  void _showBlockedAlbums() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final items = _blockedAlbums.value.toList()
          ..sort((a, b) => pinyinKey(a).compareTo(pinyinKey(b)));
        return AppSheetPanel(
          title: '已屏蔽的专辑',
          expand: true,
          child: items.isEmpty
              ? const Center(child: Text('暂无'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final name = items[index];
                    return ListTile(
                      title: Text(name),
                      trailing: IconButton(
                        icon: const Icon(Icons.undo_rounded),
                        onPressed: () async {
                          await _unblockAlbum(name);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _scrollToIndex(int index, BuildContext context) {
    if (!_controller.hasClients) return;
    final headerHeight =
        (_showBlockedEntry.value && _blockedAlbums.value.isNotEmpty) ? 64.0 + 8.0 : 8.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final totalSpacing = 14.0 * (_gridColumns.value - 1);
    final totalPadding = 12.0 + 12.0;
    final itemWidth =
        (screenWidth - totalPadding - totalSpacing) / _gridColumns.value;
    final aspectRatio = _gridAspectRatioForColumns(_gridColumns.value);
    final itemHeight = itemWidth / aspectRatio;
    final rowHeight =
        itemHeight + _gridMainAxisSpacingForColumns(_gridColumns.value);
    final rowIndex = (index / _gridColumns.value).floor();
    final offset = rowIndex * rowHeight + headerHeight;
    final max = _controller.position.maxScrollExtent;
    _controller.jumpTo(offset.clamp(0.0, max));
  }

  Widget _buildGrid(BuildContext context) {
    final theme = Theme.of(context);
    final headerCount =
        (_showBlockedEntry.value && _blockedAlbums.value.isNotEmpty) ? 1 : 0;
    final showIndexBar = _groups.value.isNotEmpty;
    return Stack(
      children: [
        CustomScrollView(
          controller: _controller,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            if (headerCount == 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SizedBox(
                    height: 64,
                    child: Material(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _showBlockedAlbums,
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            Icon(Icons.album_outlined, color: theme.colorScheme.error),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('已屏蔽的专辑')),
                            Text('${_blockedAlbums.value.length} 个'),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right_rounded),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 160),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final g = _groups.value[index];
                    final artist = primaryArtistLabel(g.representative.artist);
                    final year = g.representative.fileModifiedMs == null
                        ? ''
                        : DateTime.fromMillisecondsSinceEpoch(
                            g.representative.fileModifiedMs!,
                          ).year.toString();
                    final subtitle = year.isEmpty
                        ? '${g.songCount}首 $artist'
                        : '${g.songCount}首 $year $artist';
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailPage(albumName: g.name),
                          ),
                        );
                      },
                      onLongPress: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (context) {
                            return AppSheetPanel(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.album_outlined, color: Colors.red),
                                    title: const Text('屏蔽专辑'),
                                    titleTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
                                    onTap: () async {
                                      Navigator.pop(context);
                                      await _blockAlbum(g.name);
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gapAfterArtwork = 8.0;
                            const gapAfterTitle = 3.0;
                            const titleStyle = TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            );
                            final subtitleStyle =
                                (theme.textTheme.bodySmall ?? const TextStyle())
                                    .copyWith(
                              fontSize: 12,
                              height: 1.1,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.7),
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, box) {
                                      final size = box.maxWidth.clamp(
                                        0.0,
                                        box.maxHeight.clamp(0.0, double.infinity),
                                      );
                                      if (size <= 0) return const SizedBox.shrink();
                                      return Align(
                                        alignment: Alignment.topLeft,
                                        child: ArtworkWidget(
                                          song: g.representative,
                                          size: size,
                                          borderRadius: 16,
                                          placeholder: Container(
                                            width: size,
                                            height: size,
                                            decoration: BoxDecoration(
                                              color: theme.cardColor,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: gapAfterArtwork),
                                Text(
                                  g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                                const SizedBox(height: gapAfterTitle),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                  childCount: _groups.value.length,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _gridColumns.value,
                  crossAxisSpacing: 14,
                  mainAxisSpacing:
                      _gridMainAxisSpacingForColumns(_gridColumns.value),
                  childAspectRatio: _gridAspectRatioForColumns(_gridColumns.value),
                ),
              ),
            ),
          ],
        ),
        if (showIndexBar)
          Positioned(
            right: 0,
            top: 4,
            bottom: 4,
            child: DraggableScrollbar(
              controller: _controller,
              itemCount: _groups.value.length,
              itemExtent: 0,
              getLabel: (index) {
                final name = _groups.value[index].name;
                if (name == '未知专辑') return '↑';
                return IndexUtils.leadingLetter(name);
              },
              onIndexChanged: _activateIndexPreview,
              onScrollRequest: (index) => _scrollToIndex(index, context),
              onDragEnd: _scheduleHideIndexPreview,
            ),
          ),
        IndexPreview(
          text: _indexPreviewLetter.value ?? '',
          visible: _indexPreviewVisible.value,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      scaffoldKey: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '专辑',
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: _openDrawer,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          SortActionButton(onTap: _showSortSheet),
        ],
      ),
      drawer: const SideMenu(),
      body: Watch.builder(
        builder: (context) {
          final headerCount = (_showBlockedEntry.value && _blockedAlbums.value.isNotEmpty) ? 1 : 0;
          return RefreshIndicator(
            onRefresh: _load,
            child: _sortMode.value == 'year'
                ? ListView.builder(
                        controller: _controller,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
                        itemCount: headerCount + _groups.value.length,
                        itemBuilder: (context, index) {
                          if (headerCount == 1 && index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: MediaListTile(
                                leading: const Icon(Icons.album_outlined, color: Colors.red),
                                title: '已屏蔽的专辑',
                                subtitle: '${_blockedAlbums.value.length} 个',
                                selected: false,
                                multiSelect: false,
                                isHighlighted: false,
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: _showBlockedAlbums,
                              ),
                            );
                          }
                          final g = _groups.value[index - headerCount];
                          final year = g.representative.fileModifiedMs == null
                              ? ''
                              : DateTime.fromMillisecondsSinceEpoch(
                                  g.representative.fileModifiedMs!,
                                ).year.toString();
                          final artist = primaryArtistLabel(g.representative.artist);
                          return MediaListTile(
                            leading: ArtworkWidget(
                              song: g.representative,
                              size: 44,
                              borderRadius: 10,
                              placeholder: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            title: g.name,
                            subtitle: year.isEmpty
                                ? '$artist · ${g.songCount} 首'
                                : '$artist · ${g.songCount} 首 · $year',
                            selected: false,
                            multiSelect: false,
                            isHighlighted: false,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AlbumDetailPage(albumName: g.name),
                                ),
                              );
                            },
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (context) {
                                  return AppSheetPanel(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.album_outlined, color: Colors.red),
                                          title: const Text('屏蔽专辑'),
                                          titleTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
                                          onTap: () async {
                                            Navigator.pop(context);
                                            await _blockAlbum(g.name);
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      )
                    : _buildGrid(context),
          );
        },
      ),
      bottomNavIndex: null,
      onBottomNavTap: null,
    );
  }
}

List<Map<String, dynamic>> _buildAlbumGroups(Map<String, dynamic> payload) {
  final rawSongs = (payload['songs'] as List).cast<Map>();
  final blocked = (payload['blocked'] as List).cast<String>().toSet();
  final sortMode = (payload['sortMode'] as String?) ?? 'name';
  final ascending = payload['ascending'] == true;
  final map = <String, List<Map<String, dynamic>>>{};
  for (final raw in rawSongs) {
    final albumRaw = (raw['album']?.toString() ?? '').trim();
    final key = albumRaw.isEmpty ? '未知专辑' : albumRaw;
    map.putIfAbsent(key, () => []).add(raw.cast<String, dynamic>());
  }
  final groups = map.entries
      .where((e) => !blocked.contains(e.key))
      .map(
        (e) => {
          'name': e.key,
          'songCount': e.value.length,
          'representative': e.value.first,
        },
      )
      .toList();

  int yearOf(Map<String, dynamic> g) {
    final rep = g['representative'] as Map<String, dynamic>;
    final ms = rep['fileModifiedMs'];
    final value = ms is int ? ms : int.tryParse(ms?.toString() ?? '') ?? 0;
    if (value <= 0) return 0;
    return DateTime.fromMillisecondsSinceEpoch(value).year;
  }

  int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (sortMode == 'songCount') {
      return (a['songCount'] as int).compareTo(b['songCount'] as int);
    }
    if (sortMode == 'artist') {
      final repA = a['representative'] as Map<String, dynamic>;
      final repB = b['representative'] as Map<String, dynamic>;
      final aa = primaryArtistLabel(repA['artist']?.toString() ?? '');
      final bb = primaryArtistLabel(repB['artist']?.toString() ?? '');
      return pinyinKey(aa).compareTo(pinyinKey(bb));
    }
    if (sortMode == 'year') {
      return yearOf(a).compareTo(yearOf(b));
    }
    return pinyinKey(a['name'] as String).compareTo(pinyinKey(b['name'] as String));
  }

  groups.sort(compare);
  if (!ascending) {
    groups.replaceRange(0, groups.length, groups.reversed);
  }
  if (sortMode != 'year') {
    final idx = groups.indexWhere((g) => g['name'] == '未知专辑');
    if (idx >= 0) {
      final unknown = groups.removeAt(idx);
      groups.insert(0, unknown);
    }
  }
  return groups;
}
