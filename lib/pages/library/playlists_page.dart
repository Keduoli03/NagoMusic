import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/player_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import '../library/library_detail_pages.dart';
import '../songs/song_detail_sheet.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> with SignalsMixin {
  final PlaylistsService _service = PlaylistsService.instance;

  late final _loading = createSignal(true);
  late final _playlists = createSignal<List<PlaylistEntity>>([]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final playlists = await _service.loadAll();
    if (!mounted) return;
    _playlists.value = playlists;
    _loading.value = false;
  }

  Future<void> _createPlaylist() async {
    final name = await _showNameDialog(context, title: '新建歌单', initial: '');
    if (name == null) return;
    await _service.createPlaylist(name);
    if (!mounted) return;
    AppToast.show(context, '已创建歌单');
    await _load();
  }

  Future<void> _renamePlaylist(PlaylistEntity playlist) async {
    final name =
        await _showNameDialog(context, title: '重命名歌单', initial: playlist.name);
    if (name == null) return;
    await _service.renamePlaylist(playlist.id, name);
    if (!mounted) return;
    AppToast.show(context, '已重命名');
    await _load();
  }

  Future<void> _deletePlaylist(PlaylistEntity playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: '删除歌单',
        contentText: '确定删除「${playlist.name}」吗？',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (confirmed != true) return;
    await _service.deletePlaylist(playlist.id);
    if (!mounted) return;
    AppToast.show(context, '已删除');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '歌单',
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '新建歌单',
            icon: const Icon(Icons.add),
            onPressed: _createPlaylist,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Watch.builder(
        builder: (context) => RefreshIndicator(
          onRefresh: _load,
          child: _loading.value
              ? const Center(child: CircularProgressIndicator())
              : _playlists.value.isEmpty
                  ? const Center(child: Text('暂无歌单'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
                      itemCount: _playlists.value.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = _playlists.value[index];
                        final isFavorite = p.isFavorite;
                        return ListTile(
                          leading: Icon(
                            isFavorite
                                ? Icons.favorite
                                : Icons.queue_music_rounded,
                            color: isFavorite ? Colors.red : null,
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${p.songIds.length} 首歌曲'),
                          trailing: isFavorite
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'rename') {
                                      _renamePlaylist(p);
                                    } else if (value == 'delete') {
                                      _deletePlaylist(p);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名'),
                                    ),
                                    PopupMenuItem(value: 'delete', child: Text('删除')),
                                  ],
                                ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaylistDetailPage(playlistId: p.id),
                              ),
                            );
                            if (!mounted) return;
                            await _load();
                          },
                        );
                      },
                    ),
        ),
      ),
    );
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> with SignalsMixin {
  final PlaylistsService _service = PlaylistsService.instance;
  final SongDao _songDao = SongDao();

  late final _loading = createSignal(true);
  late final _playlist = createSignal<PlaylistEntity?>(null);
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _originalSongs = createSignal<List<SongEntity>>([]);
  late final _showCovers = createSignal(true);
  late final _isSequentialPlay = createSignal(false);
  late final _multiSelect = createSignal(false);
  late final _selectedIds = createSignal<Set<String>>({});
  late final _sortKey = createSignal('default');
  late final _sortAscending = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final all = await _service.loadAll();
    final playlist = all.where((p) => p.id == widget.playlistId).firstOrNull;
    final songs = playlist == null
        ? const <SongEntity>[]
        : await _songDao.fetchByIds(playlist.songIds);
    if (!mounted) return;
    _playlist.value = playlist;
    _songs.value = songs;
    _originalSongs.value = songs;
    _loading.value = false;
  }

  List<SongEntity> _sortedSongs(List<SongEntity> songs) {
    if (_sortKey.value == 'default') return songs;
    final list = List<SongEntity>.from(songs);
    int cmp(SongEntity a, SongEntity b) {
      switch (_sortKey.value) {
        case 'title':
          return a.title.compareTo(b.title);
        case 'artist':
          return a.artist.compareTo(b.artist);
        case 'album':
          return (a.album ?? '').compareTo(b.album ?? '');
        default:
          return 0;
      }
    }

    list.sort((a, b) => _sortAscending.value ? cmp(a, b) : -cmp(a, b));
    return list;
  }

  Future<void> _showSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SortSheet(
        options: const [
          SortOption(key: 'default', label: '添加时间', icon: Icons.sort),
          SortOption(key: 'title', label: '歌曲名称', icon: Icons.sort_by_alpha),
          SortOption(key: 'artist', label: '歌手名称', icon: Icons.person_outline),
          SortOption(key: 'album', label: '专辑名称', icon: Icons.album_outlined),
        ],
        currentKey: _sortKey.value,
        ascending: _sortAscending.value,
        onSelectKey: (key) {
          if (_sortKey.value != key) {
            _sortKey.value = key;
            _sortAscending.value = true;
          }
          _songs.value = key == 'default'
              ? _originalSongs.value
              : _sortedSongs(_songs.value);
        },
        onSelectAscending: (asc) {
          _sortAscending.value = asc;
          _songs.value = _sortKey.value == 'default'
              ? _originalSongs.value
              : _sortedSongs(_songs.value);
        },
      ),
    );
  }

  void _toggleSelectAll() {
    if (_songs.value.isEmpty) return;
    if (_selectedIds.value.length == _songs.value.length) {
      _selectedIds.value = {};
    } else {
      _selectedIds.value = _songs.value.map((e) => e.id).toSet();
    }
  }

  void _toggleMultiSelect() {
    _multiSelect.value = !_multiSelect.value;
    _selectedIds.value = {};
  }

  void _togglePlayMode() {
    _isSequentialPlay.value = !_isSequentialPlay.value;
    AppToast.show(
      context,
      _isSequentialPlay.value ? '已切换为顺序播放' : '已切换为随机播放',
    );
  }

  Future<void> _removeSong(SongEntity song) async {
    final playlist = _playlist.value;
    if (playlist == null) return;
    await _service.removeSongs(playlist.id, [song.id]);
    if (!mounted) return;
    AppToast.show(context, '已移除');
    await _load();
  }

  Future<void> _removeSongsByIds(List<String> ids) async {
    final playlist = _playlist.value;
    if (playlist == null) return;
    await _service.removeSongs(playlist.id, ids);
    if (!mounted) return;
    AppToast.show(context, '已移除');
    await _load();
  }

  Widget _coverOrIndex(
    BuildContext context,
    SongEntity song,
    int index,
    Color subtitleColor,
  ) {
    if (!_showCovers.value) {
      return Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 16,
            color: subtitleColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final coverPath = (song.localCoverPath ?? '').trim();
    if (coverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(coverPath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 16,
                  color: subtitleColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          },
        ),
      );
    }
    final letter = song.title.trim().isEmpty ? '?' : song.title.trim().substring(0, 1);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: _playlist.value?.name ?? '歌单',
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _showCovers.value ? '显示序号' : '显示封面',
            icon: Icon(
              _showCovers.value
                  ? Icons.image_outlined
                  : Icons.format_list_numbered_rounded,
            ),
            onPressed: () {
              _showCovers.value = !_showCovers.value;
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Watch.builder(
        builder: (context) {
          final playlist = _playlist.value;
          final canReorder =
              _multiSelect.value && _sortKey.value == 'default';
          final totalCount = _songs.value.length;
          final selectedCount = _selectedIds.value.length;
          final isAllSelected = totalCount > 0 && selectedCount == totalCount;
          final bottomInset =
              MediaQuery.of(context).padding.bottom + (_multiSelect.value ? 160 : 80);
          return _loading.value
              ? const Center(child: CircularProgressIndicator())
              : playlist == null
                  ? const Center(child: Text('歌单不存在'))
                  : _songs.value.isEmpty
                      ? const Center(child: Text('歌单为空'))
                      : Column(
                          children: [
                            MediaListHeader(
                              multiSelect: _multiSelect.value,
                              isAllSelected: isAllSelected,
                              selectedCount: selectedCount,
                              totalCount: totalCount,
                              isSequentialPlay: _isSequentialPlay.value,
                              onToggleSelectAll: _toggleSelectAll,
                              onPlay: () async {
                                if (_songs.value.isEmpty) return;
                                final queue = List<SongEntity>.from(_songs.value);
                                if (!_isSequentialPlay.value) {
                                  queue.shuffle();
                                }
                                await player.playQueue(queue, 0);
                              },
                              onTogglePlayMode: _togglePlayMode,
                              onSort: _showSortSheet,
                              onToggleMultiSelect: _toggleMultiSelect,
                            ),
                            Expanded(
                              child: canReorder
                                  ? ReorderableListView.builder(
                                      padding:
                                          EdgeInsets.only(bottom: bottomInset),
                                      buildDefaultDragHandles: false,
                                      itemCount: _songs.value.length,
                                      onReorder: (oldIndex, newIndex) async {
                                        if (oldIndex < newIndex) {
                                          newIndex -= 1;
                                        }
                                        final current = _songs.value.toList();
                                        final item = current.removeAt(oldIndex);
                                        current.insert(newIndex, item);
                                        _songs.value = current;
                                        _originalSongs.value =
                                            List<SongEntity>.from(current);
                                        final playlist = _playlist.value;
                                        if (playlist == null) return;
                                        await _service.reorderSongs(
                                          playlist.id,
                                          _songs.value.map((e) => e.id).toList(),
                                        );
                                      },
                                      itemBuilder: (context, index) {
                                        final song = _songs.value[index];
                                        return KeyedSubtree(
                                          key: ValueKey(song.id),
                                          child: _buildSongTile(
                                            context,
                                            player: player,
                                            song: song,
                                            index: index,
                                            canReorder: canReorder,
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.builder(
                                      padding:
                                          EdgeInsets.only(bottom: bottomInset),
                                      itemCount: _songs.value.length,
                                      itemBuilder: (context, index) {
                                        final song = _songs.value[index];
                                        return _buildSongTile(
                                          context,
                                          player: player,
                                          song: song,
                                          index: index,
                                          canReorder: canReorder,
                                        );
                                      },
                                    ),
                            ),
                            if (_multiSelect.value)
                              MultiSelectBottomBar(
                                actions: [
                                  MultiSelectAction(
                                    icon: Icons.queue_play_next,
                                    label: '下一首播放',
                                    onTap: _selectedIds.value.isEmpty
                                        ? null
                                        : () async {
                                            final selected = _songs.value
                                                .where((s) => _selectedIds.value.contains(s.id))
                                                .toList();
                                            await player.insertNext(selected);
                                            if (!context.mounted) return;
                                            AppToast.show(
                                              context,
                                              '已将 ${_selectedIds.value.length} 首歌曲加入下一首播放',
                                            );
                                            _toggleMultiSelect();
                                          },
                                  ),
                                  MultiSelectAction(
                                    icon: Icons.playlist_add,
                                    label: '添加到歌单',
                                    onTap: _selectedIds.value.isEmpty
                                        ? null
                                        : () async {
                                            final ids = _selectedIds.value.toList();
                                            final added =
                                                await showAddToPlaylistDialog(
                                              context,
                                              songIds: ids,
                                            );
                                            if (!mounted) return;
                                            if (added) _toggleMultiSelect();
                                          },
                                  ),
                                  MultiSelectAction(
                                    icon: Icons.delete_outline,
                                    label: '移除',
                                    isDestructive: true,
                                    onTap: _selectedIds.value.isEmpty
                                        ? null
                                        : () async {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) {
                                                return AlertDialog(
                                                  title: const Text('移除选中歌曲'),
                                                  content: Text(
                                                    '确定要从歌单中移除这 ${_selectedIds.value.length} 首歌曲吗？',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(ctx).pop(false),
                                                      child: const Text('取消'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(ctx).pop(true),
                                                      style: TextButton.styleFrom(
                                                        foregroundColor: Colors.red,
                                                      ),
                                                      child: const Text('移除'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirmed != true) return;
                                            final ids = _selectedIds.value.toList();
                                            await _removeSongsByIds(ids);
                                            if (!mounted) return;
                                            _toggleMultiSelect();
                                          },
                                  ),
                                ],
                              ),
                          ],
                        );
        },
      ),
    );
  }

  Widget _buildSongTile(
    BuildContext context, {
    required PlayerService player,
    required SongEntity song,
    required int index,
    required bool canReorder,
  }) {
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: player.currentSong,
      builder: (context, current, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isCurrent = current?.id == song.id;
        final isSelected = _selectedIds.value.contains(song.id);
        final titleColor =
            isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface;
        final subtitleColor = isCurrent
            ? theme.colorScheme.primary
            : (isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100));

        final tile = AppListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: _multiSelect.value
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                  )
                : _coverOrIndex(context, song, index, subtitleColor),
          ),
          title: song.title,
          subtitle: song.artist,
          titleColor: titleColor,
          trailing: _multiSelect.value && canReorder
              ? ReorderableDragStartListener(
                  index: index,
                  child: const SizedBox(
                    height: 40,
                    child: Icon(Icons.menu, color: Colors.grey),
                  ),
                )
              : null,
          onTap: () async {
            if (_multiSelect.value) {
              final next = _selectedIds.value.toSet();
              if (isSelected) {
                next.remove(song.id);
              } else {
                next.add(song.id);
              }
              _selectedIds.value = next;
              return;
            }
            await player.playQueue(_songs.value, index);
          },
          onLongPress: () {
            showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => SongDetailSheet(
                song: song,
                onUpdated: (_) => _load(),
                onDeleted: (_) => _load(),
                onOpenArtist: (artistName) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistDetailPage(artistName: artistName),
                    ),
                  );
                },
                onOpenAlbum: (albumName) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailPage(albumName: albumName),
                    ),
                  );
                },
              ),
            );
          },
        );

        if (_multiSelect.value) return tile;

        final playlist = _playlist.value;
        if (playlist == null) return tile;

        return Dismissible(
          key: Key('playlist_${playlist.id}_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) {
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
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('移除'),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) async {
            await _removeSong(song);
          },
          child: tile,
        );
      },
    );
  }
}

class PlaylistPickerSheet extends StatefulWidget {
  final List<String> songIds;

  const PlaylistPickerSheet({
    super.key,
    required this.songIds,
  });

  @override
  State<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<PlaylistPickerSheet>
    with SignalsMixin {
  final PlaylistsService _service = PlaylistsService.instance;

  late final _loading = createSignal(true);
  late final _playlists = createSignal<List<PlaylistEntity>>([]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final playlists = await _service.loadAll();
    if (!mounted) return;
    _playlists.value = playlists;
    _loading.value = false;
  }

  Future<void> _createAndAdd() async {
    final name = await _showNameDialog(context, title: '新建歌单', initial: '');
    if (name == null) return;
    final created = await _service.createPlaylist(name);
    await _service.addSongs(created.id, widget.songIds);
    if (!mounted) return;
    AppToast.show(context, '已收藏到歌单');
    Navigator.of(context).pop(true);
  }

  Future<void> _addToPlaylist(PlaylistEntity playlist) async {
    await _service.addSongs(playlist.id, widget.songIds);
    if (!mounted) return;
    AppToast.show(context, '已收藏到歌单');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      title: '选择歌单',
      expand: true,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Watch.builder(
        builder: (context) => _loading.value
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建歌单'),
                    onTap: _createAndAdd,
                  ),
                  const Divider(height: 1),
                  if (_playlists.value.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('暂无歌单')),
                    )
                  else
                    ..._playlists.value.map(
                      (p) => ListTile(
                        leading: Icon(
                          p.isFavorite
                              ? Icons.favorite
                              : Icons.queue_music_rounded,
                          color: p.isFavorite ? Colors.red : null,
                        ),
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${p.songIds.length} 首歌曲'),
                        onTap: () => _addToPlaylist(p),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<bool> showAddToPlaylistDialog(
  BuildContext context, {
  required List<String> songIds,
}) async {
  final ids = songIds.where((e) => e.trim().isNotEmpty).toList();
  if (ids.isEmpty) return false;

  final service = PlaylistsService.instance;
  final playlists = await service.loadAll();
  if (!context.mounted) return false;

  Future<void> showCreateDialog() async {
    final name = await _showNameDialog(context, title: '新建歌单', initial: '');
    if (name == null) return;
    final created = await service.createPlaylist(name);
    await service.addSongs(created.id, ids);
    if (!context.mounted) return;
    AppToast.show(context, '已添加到歌单: ${created.name}');
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AppDialog(
        title: '添加到歌单',
        confirmText: '新建歌单',
        onConfirm: () {
          Future.microtask(showCreateDialog);
        },
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: playlists.isEmpty
              ? const Center(
                  child: Text(
                    '暂无歌单',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return AppListTile(
                      leading: Icon(
                        playlist.isFavorite
                            ? Icons.favorite
                            : Icons.queue_music,
                        color: playlist.isFavorite
                            ? Colors.red
                            : Theme.of(context)
                                .iconTheme
                                .color
                                ?.withValues(alpha: 0.7),
                      ),
                      title: playlist.name,
                      subtitle: '${playlist.songIds.length} 首',
                      onTap: () async {
                        await service.addSongs(playlist.id, ids);
                        if (!context.mounted) return;
                        Navigator.pop(dialogContext, true);
                        AppToast.show(context, '已添加到歌单: ${playlist.name}');
                      },
                    );
                  },
                ),
        ),
      );
    },
  );
  return result == true;
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '歌单名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () {
                          final name = controller.text.trim();
                          Navigator.of(context).pop(name.isEmpty ? '新建歌单' : name);
                        },
                        child: const Text('确定'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  controller.dispose();
  return result;
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
