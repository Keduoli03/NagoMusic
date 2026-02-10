import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/db/dao/song_dao.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import 'library_detail_pages.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistGroup {
  final String name;
  final int songCount;
  final int albumCount;
  final SongEntity representative;

  const _ArtistGroup({
    required this.name,
    required this.songCount,
    required this.albumCount,
    required this.representative,
  });
}

class _ArtistsPageState extends State<ArtistsPage> with SignalsMixin {
  static const double _itemExtent = 64;
  static const String _prefsSortKey = 'artists_sort_key_v1';
  static const String _prefsSortAscending = 'artists_sort_ascending_v1';
  static const String _prefsFilterUnknown = 'artists_filter_unknown_v1';
  static const String _prefsShowBlockedEntry = 'artists_show_blocked_entry_v1';
  static const String _prefsBlockedArtists = 'blocked_artists_v1';

  final SongDao _songDao = SongDao();
  final ScrollController _controller = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final _loading = createSignal(true);
  late final _groups = createSignal<List<_ArtistGroup>>([]);
  late final _sortKey = createSignal('name');
  late final _ascending = createSignal(true);
  late final _filterUnknown = createSignal(false);
  late final _showBlockedEntry = createSignal(true);
  late final _blockedArtists = createSignal<Set<String>>({});

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadPrefs();
    await _load();
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var key = (prefs.getString(_prefsSortKey) ?? 'name').trim();
    if (key.isEmpty) key = 'name';
    final asc = prefs.getBool(_prefsSortAscending) ?? true;
    final filterUnknown = prefs.getBool(_prefsFilterUnknown) ?? false;
    final showBlockedEntry = prefs.getBool(_prefsShowBlockedEntry) ?? true;
    final blocked = prefs.getStringList(_prefsBlockedArtists) ?? const <String>[];
    _sortKey.value = key;
    _ascending.value = asc;
    _filterUnknown.value = filterUnknown;
    _showBlockedEntry.value = showBlockedEntry;
    _blockedArtists.value =
        blocked.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSortKey, _sortKey.value);
    await prefs.setBool(_prefsSortAscending, _ascending.value);
    await prefs.setBool(_prefsFilterUnknown, _filterUnknown.value);
    await prefs.setBool(_prefsShowBlockedEntry, _showBlockedEntry.value);
    await prefs.setStringList(
        _prefsBlockedArtists, _blockedArtists.value.toList()..sort());
  }

  Future<void> _load() async {
    _loading.value = true;
    final songs = await _songDao.fetchAll();
    final groups = await compute(
      _buildArtistGroups,
      {
        'songs': songs.map((e) => e.toMap()).toList(),
        'blocked': _blockedArtists.value.toList(),
        'sortKey': _sortKey.value,
        'ascending': _ascending.value,
        'filterUnknown': _filterUnknown.value,
      },
    );

    if (!mounted) return;
    _groups.value = groups
        .map(
          (e) => _ArtistGroup(
            name: e['name'] as String,
            songCount: e['songCount'] as int,
            albumCount: e['albumCount'] as int,
            representative: SongEntity.fromMap(
              (e['representative'] as Map).cast<String, dynamic>(),
            ),
          ),
        )
        .toList();
    _loading.value = false;
  }

  void _sortGroups(List<_ArtistGroup> groups) {
    if (_filterUnknown.value) {
      groups.removeWhere((g) => g.name == '未知艺术家');
    }

    int compare(_ArtistGroup a, _ArtistGroup b) {
      if (_sortKey.value == 'songCount') {
        return a.songCount.compareTo(b.songCount);
      }
      if (_sortKey.value == 'albumCount') {
        return a.albumCount.compareTo(b.albumCount);
      }
      return pinyinKey(a.name).compareTo(pinyinKey(b.name));
    }

    groups.sort(compare);
    if (!_ascending.value) {
      groups.replaceRange(0, groups.length, groups.reversed);
    }
    if (!_filterUnknown.value) {
      final idx = groups.indexWhere((g) => g.name == '未知艺术家');
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
      builder: (context) {
        var nextKey = _sortKey.value;
        var nextAsc = _ascending.value;
        var nextFilterUnknown = _filterUnknown.value;
        var nextShowBlockedEntry = _showBlockedEntry.value;

        void apply() {
          _sortKey.value = nextKey;
          _ascending.value = nextAsc;
          _filterUnknown.value = nextFilterUnknown;
          _showBlockedEntry.value = nextShowBlockedEntry;
          final groups = _groups.value.toList();
          _sortGroups(groups);
          _groups.value = groups;
          _savePrefs();
        }

        Widget optionRow({
          required String label,
          required String key,
          required IconData icon,
        }) {
          final selected = nextKey == key;
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: selected ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              nextKey = key;
              apply();
            },
          );
        }

        return StatefulBuilder(
          builder: (context, setInner) {
            void update(void Function() fn) {
              setInner(fn);
              apply();
            }

            return AppSheetPanel(
              title: '排序',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  optionRow(
                    label: '名称',
                    key: 'name',
                    icon: Icons.sort_by_alpha,
                  ),
                  optionRow(
                    label: '歌曲数',
                    key: 'songCount',
                    icon: Icons.music_note_outlined,
                  ),
                  optionRow(
                    label: '专辑数',
                    key: 'albumCount',
                    icon: Icons.album_outlined,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('升序'),
                    value: nextAsc,
                    onChanged: (v) => update(() => nextAsc = v),
                  ),
                  SwitchListTile(
                    title: const Text('过滤未知艺术家'),
                    value: nextFilterUnknown,
                    onChanged: (v) => update(() => nextFilterUnknown = v),
                  ),
                  SwitchListTile(
                    title: const Text('显示已屏蔽入口'),
                    value: nextShowBlockedEntry,
                    onChanged: (v) => update(() => nextShowBlockedEntry = v),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _blockArtist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _blockedArtists.value = {..._blockedArtists.value, trimmed};
    await _savePrefs();
    if (!mounted) return;
    AppToast.show(context, '已屏蔽艺术家: $trimmed', type: ToastType.success);
    await _load();
  }

  Future<void> _unblockArtist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = _blockedArtists.value.toSet();
    next.remove(trimmed);
    _blockedArtists.value = next;
    await _savePrefs();
    if (!mounted) return;
    await _load();
  }

  void _showBlockedArtists() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final items = _blockedArtists.value.toList()
          ..sort((a, b) => pinyinKey(a).compareTo(pinyinKey(b)));
        return AppSheetPanel(
          title: '已屏蔽的艺术家',
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
                          await _unblockArtist(name);
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

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      scaffoldKey: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '艺术家',
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
          final headerCount =
              (_showBlockedEntry.value && _blockedArtists.value.isNotEmpty) ? 1 : 0;
          final itemCount = _groups.value.length + headerCount;
          return RefreshIndicator(
            onRefresh: _load,
            child: MediaListView(
              controller: _controller,
              itemCount: itemCount,
              itemExtent: _itemExtent,
              isLoading: false,
              emptyText: '暂无艺术家',
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
              indexLabelBuilder: (index) {
                if (index < headerCount) return '';
                final name = _groups.value[index - headerCount].name;
                if (name == '未知艺术家') return '↑';
                return IndexUtils.leadingLetter(name);
              },
              itemBuilder: (context, index) {
                if (headerCount == 1 && index == 0) {
                  return MediaListTile(
                    leading: const Icon(Icons.person_off_outlined, color: Colors.red),
                    title: '已屏蔽的艺术家',
                    subtitle: '${_blockedArtists.value.length} 个',
                    selected: false,
                    multiSelect: false,
                    isHighlighted: false,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showBlockedArtists,
                  );
                }
                final g = _groups.value[index - headerCount];
                final initial = g.name.isNotEmpty ? g.name.characters.first : '?';
                return MediaListTile(
                  leading: ArtworkWidget(
                    song: g.representative,
                    size: 44,
                    borderRadius: 22,
                    placeholder: CircleAvatar(radius: 22, child: Text(initial)),
                  ),
                  title: g.name,
                  subtitle: '专辑：${g.albumCount}  歌曲：${g.songCount}',
                  selected: false,
                  multiSelect: false,
                  isHighlighted: false,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailPage(artistName: g.name),
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
                                leading: const Icon(Icons.person_off_outlined, color: Colors.red),
                                title: const Text('屏蔽艺术家'),
                                titleTextStyle: TextStyle(color: Theme.of(context).colorScheme.error),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _blockArtist(g.name);
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
            ),
          );
        },
      ),
      bottomNavIndex: null,
      onBottomNavTap: null,
    );
  }
}

List<Map<String, dynamic>> _buildArtistGroups(Map<String, dynamic> payload) {
  final rawSongs = (payload['songs'] as List).cast<Map>();
  final blocked = (payload['blocked'] as List).cast<String>().toSet();
  final sortKey = (payload['sortKey'] as String?) ?? 'name';
  final ascending = payload['ascending'] == true;
  final filterUnknown = payload['filterUnknown'] == true;

  final songCounts = <String, int>{};
  final albumNames = <String, Set<String>>{};
  final representative = <String, Map<String, dynamic>>{};
  for (final raw in rawSongs) {
    final artistRaw = raw['artist']?.toString().trim() ?? '';
    final names =
        artistRaw.isEmpty ? const ['未知艺术家'] : splitArtists(artistRaw);
    for (final name in names) {
      songCounts[name] = (songCounts[name] ?? 0) + 1;
      final rawAlbum = (raw['album']?.toString() ?? '').trim();
      final album = rawAlbum.isEmpty ? '未知专辑' : rawAlbum;
      albumNames.putIfAbsent(name, () => <String>{}).add(album);
      representative.putIfAbsent(name, () => raw.cast<String, dynamic>());
    }
  }
  final groups = songCounts.keys
      .where((name) => !blocked.contains(name))
      .map(
        (name) => {
          'name': name,
          'songCount': songCounts[name] ?? 0,
          'albumCount': albumNames[name]?.length ?? 0,
          'representative': representative[name]!,
        },
      )
      .toList();

  if (filterUnknown) {
    groups.removeWhere((g) => g['name'] == '未知艺术家');
  }

  int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (sortKey == 'songCount') {
      return (a['songCount'] as int).compareTo(b['songCount'] as int);
    }
    if (sortKey == 'albumCount') {
      return (a['albumCount'] as int).compareTo(b['albumCount'] as int);
    }
    return pinyinKey(a['name'] as String).compareTo(pinyinKey(b['name'] as String));
  }

  groups.sort(compare);
  if (!ascending) {
    groups.replaceRange(0, groups.length, groups.reversed);
  }
  if (!filterUnknown) {
    final idx = groups.indexWhere((g) => g['name'] == '未知艺术家');
    if (idx >= 0) {
      final unknown = groups.removeAt(idx);
      groups.insert(0, unknown);
    }
  }
  return groups;
}
