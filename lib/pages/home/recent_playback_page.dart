import 'package:flutter/material.dart';

import '../../app/router/app_page_route.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/player_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_surfaces.dart';
import '../../components/common/app_list_tile.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/common/glass_panel.dart';
import '../../components/common/letter_artwork_placeholder.dart';
import '../../components/layout/base/app_page_scaffold.dart';
import '../../components/layout/base/app_top_bar.dart';
import '../library/library_detail_pages.dart';
import '../library/playlists_page.dart';

enum RecentPlaybackTab { songs, albums, playlists }

class RecentPlaybackPage extends StatefulWidget {
  final RecentPlaybackTab initialTab;

  const RecentPlaybackPage({
    super.key,
    this.initialTab = RecentPlaybackTab.songs,
  });

  @override
  State<RecentPlaybackPage> createState() => _RecentPlaybackPageState();
}

class _RecentPlaybackPageState extends State<RecentPlaybackPage> {
  final StatsService _statsService = StatsService.instance;
  final SongDao _songDao = SongDao();
  final PlaylistsService _playlistsService = PlaylistsService.instance;
  final PlayerService _player = PlayerService.instance;

  late RecentPlaybackTab _tab;
  bool _loading = true;
  List<_RecentSongRow> _songs = [];
  List<_RecentAlbumRow> _albums = [];
  List<_RecentPlaylistRow> _playlists = [];

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    final recentSongsFuture = _statsService.fetchRecentSongs(limit: 50);
    final recentAlbumsFuture = _statsService.fetchRecentAlbums(limit: 50);
    final recentPlaylistsFuture = _statsService.fetchRecentPlaylists(limit: 50);
    final playlistsFuture = _playlistsService.loadAll();

    final recentSongs = await recentSongsFuture;
    final recentAlbums = await recentAlbumsFuture;
    final recentPlaylists = await recentPlaylistsFuture;
    final playlists = await playlistsFuture;

    final songs = await _songDao.fetchByIds(
      recentSongs.map((e) => e.songId).where((e) => e.isNotEmpty).toList(),
    );
    final songMap = <String, SongEntity>{
      for (final song in songs) song.id: song,
    };

    final songRows = recentSongs
        .map((stat) {
          final song = songMap[stat.songId];
          if (song == null) return null;
          return _RecentSongRow(song: song, stat: stat);
        })
        .whereType<_RecentSongRow>()
        .toList();

    final albumRows = recentAlbums
        .map((stat) {
          final match = songRows
              .map((row) => row.song)
              .where((song) {
                final album = (song.album ?? '').trim().isEmpty
                    ? '未知专辑'
                    : song.album!.trim();
                return album == stat.albumName;
              })
              .cast<SongEntity?>()
              .firstWhere((song) => song != null, orElse: () => null);
          if (match == null) return null;
          return _RecentAlbumRow(representative: match, stat: stat);
        })
        .whereType<_RecentAlbumRow>()
        .toList();

    final playlistMap = <String, PlaylistEntity>{
      for (final playlist in playlists) playlist.id: playlist,
    };
    final playlistRows = recentPlaylists
        .map((stat) {
          final playlist = playlistMap[stat.playlistId];
          if (playlist == null) return null;
          return _RecentPlaylistRow(playlist: playlist, stat: stat);
        })
        .whereType<_RecentPlaylistRow>()
        .toList();

    if (!mounted) return;
    setState(() {
      _songs = songRows;
      _albums = albumRows;
      _playlists = playlistRows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '最近播放',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 140),
          children: [
            _buildTabBar(context),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ListTileTheme(
                minLeadingWidth: 0,
                horizontalTitleGap: 10,
                minVerticalPadding: 0,
                child: _buildList(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(4),
      color: Theme.of(context).appPanelElevatedColor,
      child: Row(
        children: [
          _tabButton(context, label: '歌曲', tab: RecentPlaybackTab.songs),
          _tabButton(context, label: '专辑', tab: RecentPlaybackTab.albums),
          _tabButton(context, label: '歌单', tab: RecentPlaybackTab.playlists),
        ],
      ),
    );
  }

  Widget _tabButton(
    BuildContext context, {
    required String label,
    required RecentPlaybackTab tab,
  }) {
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tab = tab;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    switch (_tab) {
      case RecentPlaybackTab.songs:
        if (_songs.isEmpty) return const Center(child: Text('暂无最近播放歌曲'));
        final queue = _songs.map((e) => e.song).toList();
        return _RecentPanel(
          child: Column(
            children: _songs.map((row) {
              final subtitle = [
                row.song.artist.trim(),
                (row.song.album ?? '').trim().isEmpty
                    ? '未知专辑'
                    : row.song.album!.trim(),
                '播放 ${row.stat.playCount} 次',
              ].join(' · ');
              return AppListTile(
                leading: ArtworkWidget(
                  song: row.song,
                  size: 46,
                  borderRadius: 10,
                  placeholder: LetterArtworkPlaceholder(
                    size: 46,
                    fontWeight: FontWeight.w700,

                    label: row.song.title.isEmpty ? '?' : row.song.title[0],
                  ),
                ),
                title: row.song.title,
                subtitle: subtitle,
                contentPadding: const EdgeInsets.only(left: 8, right: 6),
                onTap: () async {
                  final index = queue.indexWhere(
                    (song) => song.id == row.song.id,
                  );
                  if (index < 0) return;
                  await _player.playQueue(queue, index);
                },
              );
            }).toList(),
          ),
        );
      case RecentPlaybackTab.albums:
        if (_albums.isEmpty) return const Center(child: Text('暂无最近播放专辑'));
        return _RecentPanel(
          child: Column(
            children: _albums.map((row) {
              final artist = row.representative.artist.trim().isEmpty
                  ? '未知艺术家'
                  : row.representative.artist.trim();
              return AppListTile(
                leading: ArtworkWidget(
                  song: row.representative,
                  size: 46,
                  borderRadius: 10,
                  placeholder: LetterArtworkPlaceholder(
                    size: 46,
                    fontWeight: FontWeight.w700,

                    label: row.stat.albumName.isEmpty
                        ? '?'
                        : row.stat.albumName[0],
                  ),
                ),
                title: row.stat.albumName,
                subtitle: '$artist · 播放 ${row.stat.playCount} 次',
                contentPadding: const EdgeInsets.only(left: 8, right: 6),
                onTap: () {
                  Navigator.of(context).push(
                    buildAppPageRoute(
                      (_) => AlbumDetailPage(albumName: row.stat.albumName),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
      case RecentPlaybackTab.playlists:
        if (_playlists.isEmpty) return const Center(child: Text('暂无最近播放歌单'));
        return _RecentPanel(
          child: Column(
            children: _playlists.map((row) {
              final subtitle = row.playlist.isFavorite
                  ? '我喜欢 · ${row.playlist.songIds.length} 首 · 播放 ${row.stat.playCount} 次'
                  : '${row.playlist.songIds.length} 首 · 播放 ${row.stat.playCount} 次';
              return AppListTile(
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    row.playlist.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.queue_music_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: row.playlist.name,
                subtitle: subtitle,
                contentPadding: const EdgeInsets.only(left: 8, right: 6),
                onTap: () {
                  Navigator.of(context).push(
                    buildAppPageRoute(
                      (_) => PlaylistDetailPage(playlistId: row.playlist.id),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
    }
  }
}

class _RecentPanel extends StatelessWidget {
  final Widget child;

  const _RecentPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).appPanelElevatedColor,
      child: child,
    );
  }
}

class _RecentSongRow {
  final SongEntity song;
  final SongListeningStat stat;

  const _RecentSongRow({required this.song, required this.stat});
}

class _RecentAlbumRow {
  final SongEntity representative;
  final AlbumPlaybackStat stat;

  const _RecentAlbumRow({required this.representative, required this.stat});
}

class _RecentPlaylistRow {
  final PlaylistEntity playlist;
  final PlaylistPlaybackStat stat;

  const _RecentPlaylistRow({required this.playlist, required this.stat});
}
