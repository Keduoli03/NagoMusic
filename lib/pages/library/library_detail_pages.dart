import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/router/app_page_route.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/player_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import '../songs/show_song_detail_sheet.dart';

List<String> splitArtists(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  final normalized = text
      .replaceAll(' feat. ', '&')
      .replaceAll(' ft. ', '&')
      .replaceAll('Feat.', '&')
      .replaceAll('FT.', '&')
      .replaceAll('Feat', '&')
      .replaceAll('Ft', '&');
  final separators = ['&', '/', '、', '，', ',', ';', '；'];
  var parts = <String>[normalized];
  for (final sep in separators) {
    parts = parts.expand((p) => p.split(sep)).toList();
  }
  final out = <String>[];
  for (final p in parts) {
    final v = p.trim();
    if (v.isEmpty) continue;
    out.add(v);
  }
  return out;
}

String primaryArtistLabel(String rawArtist) {
  final list = splitArtists(rawArtist);
  if (list.isEmpty) return '未知艺术家';
  if (list.length == 1) return list.first;
  return '${list.first} 等';
}

String albumYearFromSongs(List<SongEntity> songs) {
  if (songs.isEmpty) return '';
  final years = <int>[];
  for (final s in songs) {
    final ms = s.fileModifiedMs;
    if (ms == null || ms <= 0) continue;
    years.add(DateTime.fromMillisecondsSinceEpoch(ms).year);
  }
  if (years.isEmpty) return '';
  years.sort();
  final y = years.first;
  return y <= 0 ? '' : y.toString();
}

String pinyinKey(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  final p = PinyinHelper.getPinyin(
    trimmed,
    separator: '',
    format: PinyinFormat.WITHOUT_TONE,
  );
  return (p.isNotEmpty ? p : trimmed).toLowerCase();
}

List<SongEntity> sortAlbumDetailSongs(
  Iterable<SongEntity> songs, {
  required String sortKey,
  required bool ascending,
}) {
  final sorted = songs.toList();

  int albumOrder(SongEntity a, SongEntity b) {
    final discA = (a.discNumber ?? 1) > 0 ? (a.discNumber ?? 1) : 1;
    final discB = (b.discNumber ?? 1) > 0 ? (b.discNumber ?? 1) : 1;
    var result = discA.compareTo(discB);
    if (result != 0) return result;

    final trackA = (a.trackNumber ?? 0) > 0 ? a.trackNumber! : 1 << 30;
    final trackB = (b.trackNumber ?? 0) > 0 ? b.trackNumber! : 1 << 30;
    result = trackA.compareTo(trackB);
    if (result != 0) return result;
    return pinyinKey(a.title).compareTo(pinyinKey(b.title));
  }

  int compare(SongEntity a, SongEntity b) {
    switch (sortKey) {
      case 'title':
        return pinyinKey(a.title).compareTo(pinyinKey(b.title));
      case 'artist':
        return pinyinKey(a.artist).compareTo(pinyinKey(b.artist));
      case 'duration':
        return (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
      case 'trackNumber':
      default:
        return albumOrder(a, b);
    }
  }

  sorted.sort((a, b) => ascending ? compare(a, b) : compare(b, a));
  return sorted;
}

Map<String, dynamic> _buildArtistDetailPayload(Map<String, dynamic> args) {
  final rawSongs = (args['songs'] as List).cast<Map>();
  final songs = rawSongs
      .map((e) => SongEntity.fromMap(e.cast<String, dynamic>()))
      .toList();
  final artistName = (args['artistName'] as String?) ?? '';
  final normalized = artistName.trim();

  final filtered = songs.where((song) {
    final raw = song.artist.trim();
    if (normalized == '未知艺术家') {
      return raw.isEmpty;
    }
    return splitArtists(raw).contains(normalized);
  }).toList();
  filtered.sort((a, b) => pinyinKey(a.title).compareTo(pinyinKey(b.title)));

  final albumNames = <String>{};
  final groupedAlbums = <String, List<SongEntity>>{};
  for (final s in filtered) {
    final raw = (s.album ?? '').trim();
    final key = raw.isEmpty ? '未知专辑' : raw;
    albumNames.add(key);
    groupedAlbums.putIfAbsent(key, () => []).add(s);
  }
  final albumGroups =
      groupedAlbums.entries
          .map(
            (e) => {
              'name': e.key,
              'songs': e.value.map((song) => song.toMap()).toList(),
            },
          )
          .toList()
        ..sort(
          (a, b) => pinyinKey(
            a['name'] as String,
          ).compareTo(pinyinKey(b['name'] as String)),
        );

  return {
    'songs': filtered.map((e) => e.toMap()).toList(),
    'albumNames': albumNames.toList(),
    'albumGroups': albumGroups,
  };
}

class ArtistDetailPage extends StatefulWidget {
  final String artistName;

  const ArtistDetailPage({super.key, required this.artistName});

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> with SignalsMixin {
  final SongDao _songDao = SongDao();

  late final _loading = createSignal(true);
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _albumsExpanded = createSignal(true);
  late final _albumNames = createSignal<Set<String>>(<String>{});
  late final _albumGroups = createSignal<List<_AlbumGroup>>([]);
  late final _representative = createSignal<SongEntity?>(null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final all = await _songDao.fetchAll();
    final payload = await compute(_buildArtistDetailPayload, {
      'songs': all.map((e) => e.toMap()).toList(),
      'artistName': widget.artistName,
    });
    if (!mounted) return;
    final songs = (payload['songs'] as List)
        .map((e) => SongEntity.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
    final albumNames = (payload['albumNames'] as List)
        .map((e) => e as String)
        .toSet();
    final albumGroups = (payload['albumGroups'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(
          (e) => _AlbumGroup(
            name: e['name'] as String,
            songs: (e['songs'] as List)
                .map(
                  (song) =>
                      SongEntity.fromMap((song as Map).cast<String, dynamic>()),
                )
                .toList(),
          ),
        )
        .toList();
    _songs.value = songs;
    _albumNames.value = albumNames;
    _albumGroups.value = albumGroups;
    _representative.value = songs.isNotEmpty ? songs.first : null;
    _loading.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        extendBodyBehindAppBar: false,
        useSafeArea: false,
        appBar: AppTopBar(
          title: widget.artistName,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Watch.builder(
          builder: (context) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final player = PlayerService.instance;
            final songs = _songs.value;
            final albumNames = _albumNames.value;
            final albums = _albumGroups.value;
            final representative = _representative.value;

            return ListView(
              padding: const EdgeInsets.only(top: 0, bottom: 160),
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
                          borderRadius: 55,
                          placeholder: CircleAvatar(
                            radius: 55,
                            child: Text(
                              widget.artistName.isEmpty
                                  ? '?'
                                  : widget.artistName.substring(0, 1),
                              style: const TextStyle(fontSize: 36),
                            ),
                          ),
                        )
                      else
                        CircleAvatar(
                          radius: 55,
                          child: Text(
                            widget.artistName.isEmpty
                                ? '?'
                                : widget.artistName.substring(0, 1),
                            style: const TextStyle(fontSize: 36),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '专辑：${albumNames.length}  歌曲：${songs.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        tooltip: '随机播放',
                        visualDensity: VisualDensity.compact,
                        onPressed: songs.isEmpty
                            ? null
                            : () async {
                                final shuffled = List<SongEntity>.from(songs)
                                  ..shuffle();
                                await player.playQueue(shuffled, 0);
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: '顺序播放',
                        visualDensity: VisualDensity.compact,
                        onPressed: songs.isEmpty
                            ? null
                            : () async {
                                await player.playQueue(songs, 0);
                              },
                      ),
                    ],
                  ),
                ),
                ...songs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;
                  return ValueListenableBuilder<SongEntity?>(
                    valueListenable: player.currentSong,
                    builder: (context, current, _) {
                      final isPlaying = current?.id == song.id;
                      final titleColor = isPlaying
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface;
                      final subtitleColor = isPlaying
                          ? theme.colorScheme.primary
                          : (isDark
                                ? Colors.white70
                                : const Color.fromARGB(255, 100, 100, 100));
                      return AppListTile(
                        leading: ArtworkWidget(
                          song: song,
                          size: 44,
                          borderRadius: 8,
                          placeholder: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              song.title.isEmpty
                                  ? '?'
                                  : song.title.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        title: song.title,
                        subtitleLeading: QualityTagBadge(song: song),
                        subtitle: song.album?.trim().isNotEmpty == true
                            ? song.album!.trim()
                            : '未知专辑',
                        titleColor: titleColor,
                        subtitleColor: subtitleColor,
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                        ),
                        onTap: () async {
                          await player.playQueue(songs, index);
                        },
                        onLongPress: () {
                          showSongDetailSheet(context, song: song);
                        },
                      );
                    },
                  );
                }),
                if (albums.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      '专辑',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Icon(
                      _albumsExpanded.value
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    onTap: () {
                      _albumsExpanded.value = !_albumsExpanded.value;
                    },
                  ),
                  if (_albumsExpanded.value)
                    ...albums.map((album) {
                      final rep = album.songs.isNotEmpty
                          ? album.songs.first
                          : representative;
                      return ListTile(
                        leading: rep == null
                            ? const SizedBox(width: 44, height: 44)
                            : ArtworkWidget(
                                song: rep,
                                size: 44,
                                borderRadius: 10,
                                placeholder: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                        title: Text(
                          album.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${album.songs.length} 首'),
                        onTap: () {
                          Navigator.of(context).push(
                            buildAppPageRoute(
                              (_) => AlbumDetailPage(albumName: album.name),
                            ),
                          );
                        },
                      );
                    }),
                ],
                const SizedBox(height: 24),
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

class AlbumDetailPage extends StatefulWidget {
  final String albumName;

  const AlbumDetailPage({super.key, required this.albumName});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> with SignalsMixin {
  final SongDao _songDao = SongDao();
  final StatsService _statsService = StatsService.instance;

  late final _loading = createSignal(true);
  late final _songs = createSignal<List<SongEntity>>([]);
  late final _showCovers = createSignal(false);
  late final _sortKey = createSignal('trackNumber');
  late final _sortAscending = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final all = await _songDao.fetchAll();
    final normalized = widget.albumName.trim();
    final filtered = all.where((song) {
      final raw = (song.album ?? '').trim();
      if (normalized == '未知专辑') {
        return raw.isEmpty || raw == '未知专辑';
      }
      return raw == normalized;
    }).toList();
    if (!mounted) return;
    _songs.value = sortAlbumDetailSongs(
      filtered,
      sortKey: _sortKey.value,
      ascending: _sortAscending.value,
    );
    _loading.value = false;
  }

  void _sortSongs() {
    _songs.value = sortAlbumDetailSongs(
      _songs.value,
      sortKey: _sortKey.value,
      ascending: _sortAscending.value,
    );
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SortSheet(
          title: '更多',
          options: const [
            SortOption(
              key: 'trackNumber',
              label: '轨道号',
              icon: Icons.format_list_numbered_rounded,
            ),
            SortOption(key: 'title', label: '歌曲名称', icon: Icons.sort_by_alpha),
            SortOption(
              key: 'artist',
              label: '歌手名称',
              icon: Icons.person_outline,
            ),
            SortOption(key: 'duration', label: '歌曲时长', icon: Icons.schedule),
          ],
          currentKey: _sortKey.value,
          ascending: _sortAscending.value,
          onSelectKey: (value) {
            _sortKey.value = value;
            _sortSongs();
          },
          onSelectAscending: (value) {
            _sortAscending.value = value;
            _sortSongs();
          },
          extra: Watch.builder(
            builder: (context) {
              return AppSettingSwitchTile(
                title: '显示专辑封面',
                subtitle: '关闭时显示歌曲序号',
                leading: const Icon(Icons.image_outlined),
                value: _showCovers.value,
                onChanged: (value) => _showCovers.value = value,
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        extendBodyBehindAppBar: false,
        useSafeArea: false,
        appBar: AppTopBar(
          title: widget.albumName,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showMoreSheet,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Watch.builder(
          builder: (context) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final player = PlayerService.instance;
            final songs = _songs.value;
            final representative = songs.isNotEmpty ? songs.first : null;
            final artistLabel = representative != null
                ? primaryArtistLabel(representative.artist)
                : '未知艺术家';
            final year = albumYearFromSongs(songs);
            final songCountText = '${songs.length}首';
            final infoText = year.isEmpty
                ? songCountText
                : '$songCountText · $year';

            final Set<String> participatingArtists = {};
            for (final song in songs) {
              participatingArtists.addAll(splitArtists(song.artist));
            }
            final sortedArtists = participatingArtists.toList()
              ..sort((a, b) => pinyinKey(a).compareTo(pinyinKey(b)));

            return ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 160),
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
                          placeholder: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: theme.cardColor,
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
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              infoText,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        tooltip: '随机播放',
                        visualDensity: VisualDensity.compact,
                        onPressed: songs.isEmpty
                            ? null
                            : () async {
                                final shuffled = List<SongEntity>.from(songs)
                                  ..shuffle();
                                await player.playQueue(shuffled, 0);
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: '顺序播放',
                        visualDensity: VisualDensity.compact,
                        onPressed: songs.isEmpty
                            ? null
                            : () async {
                                await _statsService.recordAlbumPlay(
                                  widget.albumName,
                                );
                                await player.playQueue(songs, 0);
                              },
                      ),
                    ],
                  ),
                ),
                ...songs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final song = entry.value;
                  return ValueListenableBuilder<SongEntity?>(
                    valueListenable: player.currentSong,
                    builder: (context, current, _) {
                      final isPlaying = current?.id == song.id;
                      final titleColor = isPlaying
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface;
                      final subtitleColor = isPlaying
                          ? theme.colorScheme.primary
                          : (isDark
                                ? Colors.white70
                                : const Color.fromARGB(255, 100, 100, 100));
                      return AppListTile(
                        leading: _showCovers.value
                            ? ArtworkWidget(
                                song: song,
                                size: 48,
                                borderRadius: 6,
                                placeholder: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: theme.cardColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              )
                            : SizedBox(
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
                        subtitleLeading: QualityTagBadge(song: song),
                        subtitle: song.artist,
                        titleColor: titleColor,
                        subtitleColor: subtitleColor,
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                        ),
                        onTap: () async {
                          await _statsService.recordAlbumPlay(widget.albumName);
                          await player.playQueue(songs, index);
                        },
                        onLongPress: () {
                          showSongDetailSheet(context, song: song);
                        },
                      );
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...sortedArtists.map((artist) {
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
                          buildAppPageRoute(
                            (_) => ArtistDetailPage(artistName: artist),
                          ),
                        );
                      },
                    );
                  }),
                ],
                const SizedBox(height: 24),
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

class _AlbumGroup {
  final String name;
  final List<SongEntity> songs;

  const _AlbumGroup({required this.name, required this.songs});
}
