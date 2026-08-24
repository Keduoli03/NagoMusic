import 'dart:io';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/player_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/multi_select_mixin.dart';
import '../../app/utils/natural_sort.dart';
import '../../app/utils/uri_utils.dart';
import '../../components/index.dart';
import '../songs/show_song_detail_sheet.dart';
import 'playlist_detail_controller.dart';
import 'playlist_picker_sheet.dart';

class PlaylistDetailPage extends StatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage>
    with SignalsMixin, MultiSelectMixin<PlaylistDetailPage> {
  final PlaylistDetailController _controller = PlaylistDetailController();
  final StatsService _statsService = StatsService.instance;

  late final _loading = createSignal(true);
  late final _playlist = createSignal<PlaylistEntity?>(null);
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _originalSongs = createSignal<List<SongEntity>>([]);
  late final _showCovers = createSignal(true);
  late final _isSequentialPlay = createSignal(false);
  late final _sortKey = createSignal('default');
  late final _sortAscending = createSignal(true);
  final RemoveProgressController _removeProgress = RemoveProgressController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _removeProgress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _loading.value = true;
    final result = await _controller.load(widget.playlistId);
    if (!mounted) return;
    _playlist.value = result.playlist;
    _songs.value = result.songs;
    _originalSongs.value = result.songs;
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
        case 'fileName':
          return naturalCompare(
            a.uri == null ? '' : UriUtils.extractFileName(a.uri!),
            b.uri == null ? '' : UriUtils.extractFileName(b.uri!),
          );
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
          SortOption(key: 'default', label: '添加时间', icon: AppIcons.sort),
          SortOption(key: 'title', label: '歌曲名称', icon: AppIcons.sort),
          SortOption(key: 'artist', label: '歌手名称', icon: AppIcons.person),
          SortOption(key: 'album', label: '专辑名称', icon: AppIcons.album),
          SortOption(key: 'fileName', label: '文件名称', icon: AppIcons.fileText),
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

  void _togglePlayMode() {
    _isSequentialPlay.value = !_isSequentialPlay.value;
    AppToast.show(context, _isSequentialPlay.value ? '已切换为顺序播放' : '已切换为随机播放');
  }

  Future<void> _removeSong(SongEntity song) async {
    final playlist = _playlist.value;
    if (playlist == null) return;
    await _controller.removeSong(playlist.id, song.id);
    if (!mounted) return;
    AppToast.show(context, '已移除');
    await _load();
  }

  Future<void> _removeSongsByIds(List<String> ids) async {
    if (_removeProgress.isRemoving) {
      _removeProgress.showDialogOn(context);
      return;
    }
    final playlist = _playlist.value;
    if (playlist == null) return;
    final songsToRemove = _songs.value
        .where((s) => ids.contains(s.id))
        .toList();
    _removeProgress.start(songsToRemove.length);
    _removeProgress.showDialogOn(context);
    var processed = 0;
    final removedCount = await _controller.removeSongs(
      playlistId: playlist.id,
      songsToRemove: songsToRemove,
      onSongRemoved: (song) async {
        if (!mounted) return;
        _songs.value = _songs.value.where((s) => s.id != song.id).toList();
        _originalSongs.value = _originalSongs.value
            .where((s) => s.id != song.id)
            .toList();
        removeFromSelection([song.id]);
      },
      onProgress: (nextProcessed, total) async {
        if (!mounted) return;
        processed = nextProcessed;
        _removeProgress.update(nextProcessed);
      },
    );
    if (!mounted) return;
    _removeProgress.finish(processed);
    AppToast.show(context, '已移除 $removedCount 首');
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
    final letter = song.title.trim().isEmpty
        ? '?'
        : song.title.trim().substring(0, 1);
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
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        extendBodyBehindAppBar: true,
        showMiniPlayer: !multiSelect.value,
        appBar: AppTopBar(
          title: _playlist.value?.name ?? '歌单',
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: _showCovers.value ? '显示序号' : '显示封面',
              icon: Icon(
                _showCovers.value ? AppIcons.image : AppIcons.listNumbers,
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
            final canReorder = multiSelect.value && _sortKey.value == 'default';
            final totalCount = _songs.value.length;
            final selectedCount = selection.length;
            final isAllSelected = totalCount > 0 && selectedCount == totalCount;
            final bottomInset =
                MediaQuery.of(context).padding.bottom +
                (multiSelect.value ? 160 : 80);
            return _loading.value
                ? const Center(child: CircularProgressIndicator())
                : playlist == null
                ? const Center(child: Text('歌单不存在'))
                : _songs.value.isEmpty
                ? const Center(child: Text('歌单为空'))
                : Column(
                    children: [
                      MediaListHeader(
                        multiSelect: multiSelect.value,
                        isAllSelected: isAllSelected,
                        selectedCount: selectedCount,
                        totalCount: totalCount,
                        playbackCount: totalCount,
                        isSequentialPlay: _isSequentialPlay.value,
                        onToggleSelectAll: () =>
                            toggleSelectAll(_songs.value.map((e) => e.id)),
                        onPlay: () async {
                          if (_songs.value.isEmpty) return;
                          final queue = List<SongEntity>.from(_songs.value);
                          if (!_isSequentialPlay.value) {
                            queue.shuffle();
                          }
                          await _statsService.recordPlaylistPlay(
                            widget.playlistId,
                          );
                          await player.playQueue(queue, 0);
                        },
                        onConfigurePlay: () {},
                        onTogglePlayMode: _togglePlayMode,
                        onSort: _showSortSheet,
                        onToggleMultiSelect: toggleMultiSelect,
                      ),
                      Expanded(
                        child: canReorder
                            ? ReorderableListView.builder(
                                padding: EdgeInsets.only(bottom: bottomInset),
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
                                  _originalSongs.value = List<SongEntity>.from(
                                    current,
                                  );
                                  final playlist = _playlist.value;
                                  if (playlist == null) return;
                                  await _controller.reorderSongs(
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
                                padding: EdgeInsets.only(bottom: bottomInset),
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
                      if (multiSelect.value)
                        MultiSelectBottomBar(
                          actions: [
                            MultiSelectAction(
                              icon: AppIcons.queue,
                              label: '下一首播放',
                              onTap: selection.isEmpty
                                  ? null
                                  : () async {
                                      final selected = _songs.value
                                          .where(
                                            (s) => selection.contains(s.id),
                                          )
                                          .toList();
                                      await player.insertNext(selected);
                                      if (!context.mounted) return;
                                      AppToast.show(
                                        context,
                                        '已将 ${selection.length} 首歌曲加入下一首播放',
                                      );
                                      toggleMultiSelect();
                                    },
                            ),
                            MultiSelectAction(
                              icon: AppIcons.playlist,
                              label: '添加到歌单',
                              onTap: selection.isEmpty
                                  ? null
                                  : () async {
                                      final ids = selection.toList();
                                      final added =
                                          await showAddToPlaylistDialog(
                                            context,
                                            songIds: ids,
                                          );
                                      if (!mounted) return;
                                      if (added) toggleMultiSelect();
                                    },
                            ),
                            MultiSelectAction(
                              icon: AppIcons.trash,
                              label: '移出',
                              isDestructive: true,
                              onTap: selection.isEmpty
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) {
                                          return AlertDialog(
                                            title: const Text('移出选中歌曲'),
                                            content: Text(
                                              '确定要从歌单中移出这 ${selection.length} 首歌曲吗？',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(
                                                  ctx,
                                                ).pop(false),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                ),
                                                child: const Text('移出'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                      if (confirmed != true) return;
                                      final ids = selection.toList();
                                      await _removeSongsByIds(ids);
                                      if (!mounted) return;
                                      toggleMultiSelect();
                                    },
                            ),
                          ],
                        ),
                    ],
                  );
          },
        ),
        bottomNavIndex: useBottomNavigation ? 0 : null,
        onBottomNavTap: useBottomNavigation
            ? (index) => navigateToPrimaryDestination(context, index)
            : null,
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
        final isSelected = selection.contains(song.id);
        final titleColor = isCurrent
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
        final subtitleColor = isCurrent
            ? theme.colorScheme.primary
            : (isDark
                  ? Colors.white70
                  : const Color.fromARGB(255, 100, 100, 100));

        final tile = AppListTile(
          leading: SizedBox(
            width: 48,
            height: 48,
            child: multiSelect.value
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      isSelected ? AppIcons.checkCircle : AppIcons.circle,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.disabledColor,
                    ),
                  )
                : _coverOrIndex(context, song, index, subtitleColor),
          ),
          title: song.title,
          subtitleLeading: QualityTagBadge(song: song),
          subtitle: song.artist,
          titleColor: titleColor,
          trailing: multiSelect.value && canReorder
              ? ReorderableDragStartListener(
                  index: index,
                  child: const SizedBox(
                    height: 40,
                    child: Icon(AppIcons.menu, color: Colors.grey),
                  ),
                )
              : null,
          onTap: () async {
            if (multiSelect.value) {
              toggleSelected(song.id);
              return;
            }
            await _statsService.recordPlaylistPlay(widget.playlistId);
            await player.playQueue(_songs.value, index);
          },
          onLongPress: () {
            showSongDetailSheet(
              context,
              song: song,
              onUpdated: (_) => _load(),
              onDeleted: (_) => _load(),
            );
          },
        );

        if (multiSelect.value) return tile;

        final playlist = _playlist.value;
        if (playlist == null) return tile;

        return Dismissible(
          key: Key('playlist_${playlist.id}_${song.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: Colors.red,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(AppIcons.trash, color: Colors.white),
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
