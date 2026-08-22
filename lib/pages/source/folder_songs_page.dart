import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/multi_select_mixin.dart';
import '../../app/utils/natural_sort.dart';
import '../../app/utils/uri_utils.dart';
import '../../components/index.dart';
import '../library/playlists_page.dart';
import '../songs/song_detail_sheet.dart';

class FolderSongsPage extends StatefulWidget {
  final String title;
  final String sourceId;
  final String folderPath;

  const FolderSongsPage({
    super.key,
    required this.title,
    required this.sourceId,
    required this.folderPath,
  });

  @override
  State<FolderSongsPage> createState() => _FolderSongsPageState();
}

class _FolderSongsPageState extends State<FolderSongsPage>
    with SignalsMixin, MultiSelectMixin<FolderSongsPage> {
  static const double _itemExtent = 64;

  final SongDao _songDao = SongDao();
  final ScrollController _scrollController = ScrollController();
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final RemoveProgressController _removeProgress = RemoveProgressController();

  /// 该页进入多选时保留此前的选中项，仅在退出时清空。
  @override
  bool get clearSelectionOnEnter => false;

  late final _songs = createSignal<List<SongEntity>>([]);
  late final _isLoading = createSignal(true);
  late final _currentSongId = createSignal<String?>(null);
  late final _sortKey = createSignal('title');
  late final _ascending = createSignal(true);
  late final _isSequentialPlay = createSignal(true);

  @override
  void initState() {
    super.initState();
    _loadSongs();

    // Listen to current song changes to highlight playing track
    final currentSong = PlayerService.instance.currentSong;
    _currentSongId.value = currentSong.value?.id;
    currentSong.addListener(_handleCurrentSongChanged);
  }

  @override
  void dispose() {
    PlayerService.instance.currentSong.removeListener(
      _handleCurrentSongChanged,
    );
    _scrollController.dispose();
    _removeProgress.dispose();
    super.dispose();
  }

  void _handleCurrentSongChanged() {
    if (!mounted) return;
    _currentSongId.value = PlayerService.instance.currentSong.value?.id;
  }

  Future<void> _loadSongs() async {
    final allSourceSongs = await _songDao.fetchAll(sourceId: widget.sourceId);
    final folderSongs = widget.folderPath.trim().isEmpty
        ? allSourceSongs
        : allSourceSongs.where((s) {
            if (s.uri == null) return false;
            // Normalize paths for comparison
            final songDir = p.dirname(s.uri!).replaceAll('\\', '/');
            final targetDir = widget.folderPath.replaceAll('\\', '/');
            return songDir == targetDir;
          }).toList();

    if (mounted) {
      _songs.value = folderSongs;
      _isLoading.value = false;
    }
  }

  List<SongEntity> _sortedSongs(List<SongEntity> input) {
    final list = List<SongEntity>.from(input);
    int cmpText(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    int compare(SongEntity a, SongEntity b) {
      switch (_sortKey.value) {
        case 'artist':
          return cmpText(a.artist, b.artist);
        case 'album':
          return cmpText(a.album ?? '', b.album ?? '');
        case 'duration':
          return (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
        case 'fileName':
          return naturalCompare(
            a.uri == null ? '' : UriUtils.extractFileName(a.uri!),
            b.uri == null ? '' : UriUtils.extractFileName(b.uri!),
          );
        case 'title':
        default:
          return cmpText(a.title, b.title);
      }
    }

    list.sort((a, b) => _ascending.value ? compare(a, b) : compare(b, a));
    return list;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SortSheet(
          options: const [
            SortOption(key: 'title', label: '歌曲名称', icon: Icons.sort_by_alpha),
            SortOption(
              key: 'artist',
              label: '歌手名称',
              icon: Icons.person_outline,
            ),
            SortOption(key: 'album', label: '专辑名称', icon: Icons.album_outlined),
            SortOption(key: 'duration', label: '歌曲时长', icon: Icons.schedule),
            SortOption(
              key: 'fileName',
              label: '文件名称',
              icon: Icons.description_outlined,
            ),
          ],
          currentKey: _sortKey.value,
          ascending: _ascending.value,
          onSelectKey: (value) {
            _sortKey.value = value;
          },
          onSelectAscending: (value) {
            _ascending.value = value;
          },
        );
      },
    );
  }

  void _togglePlayMode() {
    _isSequentialPlay.value = !_isSequentialPlay.value;
  }

  Future<void> _openAddToPlaylistSheet() async {
    final ids = selection.toList(growable: false);
    if (ids.isEmpty) return;
    final added = await showAddToPlaylistDialog(context, songIds: ids);
    if (!mounted) return;
    if (added) {
      toggleMultiSelect();
    }
  }

  Future<void> _removeSelectedSongs() async {
    if (_removeProgress.isRemoving) {
      _removeProgress.showDialogOn(context);
      return;
    }
    final ids = selection.toList(growable: false);
    if (ids.isEmpty) return;
    final removedSongs = _songs.value
        .where((s) => ids.contains(s.id))
        .toList(growable: false);
    _removeProgress.start(removedSongs.length);
    _removeProgress.showDialogOn(context);
    var processed = 0;
    var removedCount = 0;
    for (final song in removedSongs) {
      if (!mounted) break;
      removedCount += await _songDao.deleteByIds([song.id]);
      if (!mounted) break;
      await PlayerService.instance.removeSongsById([song.id]);
      if (!mounted) break;
      await _cleanupCachesForSongs([song]);
      if (!mounted) break;
      _songs.value = _songs.value.where((s) => s.id != song.id).toList();
      final currentId = _currentSongId.value;
      if (currentId != null && currentId == song.id) {
        _currentSongId.value = null;
      }
      removeFromSelection([song.id]);
      processed += 1;
      _removeProgress.update(processed);
    }
    if (!mounted) return;
    _removeProgress.finish(processed);
    AppToast.show(context, '已移除 $removedCount 首');
    exitMultiSelect();
  }

  Future<void> _cleanupCachesForSongs(List<SongEntity> songs) async {
    if (songs.isEmpty) return;
    for (final song in songs) {
      await _lyricsRepo.removeCachedLrc(song.id);
      final coverPath = (song.localCoverPath ?? '').trim();
      if (coverPath.isNotEmpty) {
        await ArtworkCacheHelper.removeCachedArtworkByPath(coverPath);
      }
      await ArtworkCacheHelper.removeCachedArtwork(key: song.id);
    }
  }

  void _playQueue(List<SongEntity> songs, SongEntity target) {
    if (songs.isEmpty) return;
    final queue = List<SongEntity>.from(songs);
    if (!_isSequentialPlay.value) {
      queue.shuffle();
    }
    final startIndex = queue.indexWhere((s) => s.id == target.id);
    PlayerService.instance.playQueue(queue, startIndex == -1 ? 0 : startIndex);
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        extendBodyBehindAppBar: true,
        showMiniPlayer: !multiSelect.value,
        appBar: AppTopBar(
          title: widget.title,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Watch.builder(
          builder: (context) {
            if (_isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            final songs = _sortedSongs(_songs.value);
            final currentId = _currentSongId.value;
            final selected = selection;
            final isAllSelected = this.isAllSelected(songs.length);

            if (songs.isEmpty) {
              return const Center(child: Text('此文件夹没有歌曲'));
            }

            return Column(
              children: [
                MediaListHeader(
                  multiSelect: multiSelect.value,
                  isAllSelected: isAllSelected,
                  selectedCount: selectedCount,
                  totalCount: songs.length,
                  playbackCount: songs.length,
                  isSequentialPlay: _isSequentialPlay.value,
                  onToggleSelectAll: () =>
                      toggleSelectAll(songs.map((e) => e.id)),
                  onPlay: () {
                    if (songs.isEmpty) return;
                    final queue = List<SongEntity>.from(songs);
                    if (!_isSequentialPlay.value) {
                      queue.shuffle();
                    }
                    PlayerService.instance.playQueue(queue, 0);
                  },
                  onConfigurePlay: () {},
                  onTogglePlayMode: _togglePlayMode,
                  onSort: _showSortSheet,
                  onToggleMultiSelect: toggleMultiSelect,
                ),
                Expanded(
                  child: MediaListView(
                    controller: _scrollController,
                    itemCount: songs.length,
                    itemExtent: _itemExtent,
                    bottomInset:
                        MediaQuery.of(context).padding.bottom +
                        (multiSelect.value ? 160 : 80),
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final isPlaying = song.id == currentId;
                      final isSelected = selected.contains(song.id);
                      return MediaListTile(
                        title: song.title,
                        titleBadge: QualityTagBadge(song: song),
                        subtitle: song.artist,
                        leading: ArtworkWidget(
                          song: song,
                          size: 48,
                          borderRadius: 8,
                        ),
                        isHighlighted: isPlaying,
                        selected: isSelected,
                        multiSelect: multiSelect.value,
                        onTap: () {
                          if (multiSelect.value) {
                            toggleSelected(song.id);
                            return;
                          }
                          _playQueue(songs, song);
                        },
                        onLongPress: () {
                          if (multiSelect.value) return;
                          showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => SongDetailSheet(song: song),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (multiSelect.value)
                  MultiSelectBottomBar(
                    actions: [
                      MultiSelectAction(
                        icon: Icons.queue_play_next,
                        label: '下一首播放',
                        onTap: selectedCount == 0
                            ? null
                            : () async {
                                final selectedSongs = songs
                                    .where((s) => selected.contains(s.id))
                                    .toList(growable: false);
                                await PlayerService.instance.insertNext(
                                  selectedSongs,
                                );
                                if (!context.mounted) return;
                                AppToast.show(
                                  context,
                                  '已将 $selectedCount 首歌曲加入下一首播放',
                                );
                                toggleMultiSelect();
                              },
                      ),
                      MultiSelectAction(
                        icon: Icons.playlist_add,
                        label: '收藏到歌单',
                        onTap: selectedCount == 0
                            ? null
                            : _openAddToPlaylistSheet,
                      ),
                      MultiSelectAction(
                        icon: Icons.delete_outline,
                        label: '移除',
                        isDestructive: true,
                        onTap: selectedCount == 0 ? null : _removeSelectedSongs,
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
}
