import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
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

class _FolderSongsPageState extends State<FolderSongsPage> with SignalsMixin {
  static const double _itemExtent = 64;

  final SongDao _songDao = SongDao();
  final ScrollController _scrollController = ScrollController();
  final LyricsRepository _lyricsRepo = LyricsRepository();
  
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _isLoading = createSignal(true);
  late final _currentSongId = createSignal<String?>(null);
  late final _sortKey = createSignal('title');
  late final _ascending = createSignal(true);
  late final _multiSelect = createSignal(false);
  late final _selectedIds = createSignal<Set<String>>({});
  late final _isSequentialPlay = createSignal(true);

  @override
  void initState() {
    super.initState();
    _loadSongs();
    
    // Listen to current song changes to highlight playing track
    final currentSong = PlayerService.instance.currentSong;
    _currentSongId.value = currentSong.value?.id;
    currentSong.addListener(() {
      if (mounted) {
        _currentSongId.value = currentSong.value?.id;
      }
    });
  }

  Future<void> _loadSongs() async {
    final allSourceSongs = await _songDao.fetchAll(sourceId: widget.sourceId);
    final folderSongs = allSourceSongs.where((s) {
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
    int cmpText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    int compare(SongEntity a, SongEntity b) {
      switch (_sortKey.value) {
        case 'artist':
          return cmpText(a.artist, b.artist);
        case 'album':
          return cmpText(a.album ?? '', b.album ?? '');
        case 'duration':
          return (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
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
            SortOption(key: 'artist', label: '歌手名称', icon: Icons.person_outline),
            SortOption(key: 'album', label: '专辑名称', icon: Icons.album_outlined),
            SortOption(key: 'duration', label: '歌曲时长', icon: Icons.schedule),
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

  void _toggleMultiSelect() {
    final next = !_multiSelect.value;
    _multiSelect.value = next;
    if (!next) {
      _selectedIds.value = {};
    }
  }

  void _togglePlayMode() {
    _isSequentialPlay.value = !_isSequentialPlay.value;
  }

  void _toggleSelectAll(List<SongEntity> songs) {
    final selected = _selectedIds.value;
    if (selected.length == songs.length) {
      _selectedIds.value = {};
      return;
    }
    _selectedIds.value = songs.map((e) => e.id).toSet();
  }

  Future<void> _openAddToPlaylistSheet() async {
    final ids = _selectedIds.value.toList(growable: false);
    if (ids.isEmpty) return;
    final added = await showAddToPlaylistDialog(
      context,
      songIds: ids,
    );
    if (!mounted) return;
    if (added) {
      _toggleMultiSelect();
    }
  }

  Future<void> _removeSelectedSongs() async {
    final ids = _selectedIds.value.toList(growable: false);
    if (ids.isEmpty) return;
    final removedSongs =
        _songs.value.where((s) => ids.contains(s.id)).toList(growable: false);
    final removed = await _songDao.deleteByIds(ids);
    if (!mounted) return;
    await PlayerService.instance.removeSongsById(ids);
    if (!mounted) return;
    await _cleanupCachesForSongs(removedSongs);
    if (!mounted) return;
    AppToast.show(context, '已移除 $removed 首');
    final nextSongs = _songs.value.where((s) => !ids.contains(s.id)).toList();
    _songs.value = nextSongs;
    final currentId = _currentSongId.value;
    if (currentId != null && ids.contains(currentId)) {
      _currentSongId.value = null;
    }
    _selectedIds.value = <String>{};
    _multiSelect.value = false;
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
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      showMiniPlayer: !_multiSelect.value,
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
          final selected = _selectedIds.value;
          final selectedCount = selected.length;
          final isAllSelected = songs.isNotEmpty && selectedCount == songs.length;

          if (songs.isEmpty) {
            return const Center(child: Text('此文件夹没有歌曲'));
          }

          return Column(
            children: [
              MediaListHeader(
                multiSelect: _multiSelect.value,
                isAllSelected: isAllSelected,
                selectedCount: selectedCount,
                totalCount: songs.length,
                isSequentialPlay: _isSequentialPlay.value,
                onToggleSelectAll: () => _toggleSelectAll(songs),
                onPlay: () {
                  if (songs.isEmpty) return;
                  final queue = List<SongEntity>.from(songs);
                  if (!_isSequentialPlay.value) {
                    queue.shuffle();
                  }
                  PlayerService.instance.playQueue(queue, 0);
                },
                onTogglePlayMode: _togglePlayMode,
                onSort: _showSortSheet,
                onToggleMultiSelect: _toggleMultiSelect,
              ),
              Expanded(
                child: MediaListView(
                  controller: _scrollController,
                  itemCount: songs.length,
                  itemExtent: _itemExtent,
                  bottomInset: MediaQuery.of(context).padding.bottom +
                      (_multiSelect.value ? 160 : 80),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final isPlaying = song.id == currentId;
                    final isSelected = selected.contains(song.id);
                    return MediaListTile(
                      title: song.title,
                      subtitle: song.artist,
                      leading: ArtworkWidget(
                        song: song,
                        size: 48,
                        borderRadius: 8,
                      ),
                      isHighlighted: isPlaying,
                      selected: isSelected,
                      multiSelect: _multiSelect.value,
                      onTap: () {
                        if (_multiSelect.value) {
                          final next = Set<String>.from(selected);
                          if (next.contains(song.id)) {
                            next.remove(song.id);
                          } else {
                            next.add(song.id);
                          }
                          _selectedIds.value = next;
                          return;
                        }
                        _playQueue(songs, song);
                      },
                      onLongPress: () {
                        if (_multiSelect.value) return;
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
              if (_multiSelect.value)
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
                              _toggleMultiSelect();
                            },
                    ),
                    MultiSelectAction(
                      icon: Icons.playlist_add,
                      label: '收藏到歌单',
                      onTap: selectedCount == 0 ? null : _openAddToPlaylistSheet,
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
    );
  }
}
