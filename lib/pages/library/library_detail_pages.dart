import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/index.dart';
import '../songs/song_detail_sheet.dart';

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

class ArtistDetailPage extends StatefulWidget {
  final String artistName;

  const ArtistDetailPage({
    super.key,
    required this.artistName,
  });

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  final SongDao _songDao = SongDao();

  bool _loading = true;
  List<SongEntity> _songs = const [];
  bool _albumsExpanded = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _songDao.fetchAll();
    final normalized = widget.artistName.trim();
    final filtered = all.where((song) {
      final raw = song.artist.trim();
      if (normalized == '未知艺术家') {
        return raw.isEmpty;
      }
      return splitArtists(raw).contains(normalized);
    }).toList();
    filtered.sort((a, b) => pinyinKey(a.title).compareTo(pinyinKey(b.title)));
    if (!mounted) return;
    setState(() {
      _songs = filtered;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final player = PlayerService.instance;
    final songs = _songs;

    final albumNames = <String>{};
    for (final s in songs) {
      final raw = (s.album ?? '').trim();
      albumNames.add(raw.isEmpty ? '未知专辑' : raw);
    }

    final representative = songs.isNotEmpty ? songs.first : null;

    final groupedAlbums = <String, List<SongEntity>>{};
    for (final s in songs) {
      final raw = (s.album ?? '').trim();
      final key = raw.isEmpty ? '未知专辑' : raw;
      groupedAlbums.putIfAbsent(key, () => []).add(s);
    }
    final albums = groupedAlbums.entries
        .map((e) => _AlbumGroup(name: e.key, songs: e.value))
        .toList()
      ..sort((a, b) => pinyinKey(a.name).compareTo(pinyinKey(b.name)));

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      useSafeArea: false,
      appBar: AppTopBar(
        title: widget.artistName,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                bottom: 160,
              ),
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
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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
                          subtitle: song.album?.trim().isNotEmpty == true
                              ? song.album!.trim()
                              : '未知专辑',
                          titleColor: titleColor,
                          subtitleColor: subtitleColor,
                          contentPadding:
                              const EdgeInsets.only(left: 16, right: 16),
                          onTap: () async {
                            await player.playQueue(songs, index);
                          },
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (_) => SongDetailSheet(
                                song: song,
                                onOpenArtist: (artistName) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ArtistDetailPage(
                                        artistName: artistName,
                                      ),
                                    ),
                                  );
                                },
                                onOpenAlbum: (albumName) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AlbumDetailPage(
                                        albumName: albumName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
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
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        '专辑',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      trailing: Icon(
                        _albumsExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () {
                        setState(() => _albumsExpanded = !_albumsExpanded);
                      },
                    ),
                    if (_albumsExpanded)
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
                              MaterialPageRoute(
                                builder: (_) =>
                                    AlbumDetailPage(albumName: album.name),
                              ),
                            );
                          },
                        );
                      }),
                  ],
                  const SizedBox(height: 24),
              ],
            ),
      bottomNavIndex: null,
      onBottomNavTap: null,
    );
  }
}

class AlbumDetailPage extends StatefulWidget {
  final String albumName;

  const AlbumDetailPage({
    super.key,
    required this.albumName,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final SongDao _songDao = SongDao();

  bool _loading = true;
  List<SongEntity> _songs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _songDao.fetchAll();
    final normalized = widget.albumName.trim();
    final filtered = all.where((song) {
      final raw = (song.album ?? '').trim();
      if (normalized == '未知专辑') {
        return raw.isEmpty;
      }
      return raw == normalized;
    }).toList();
    filtered.sort((a, b) => pinyinKey(a.title).compareTo(pinyinKey(b.title)));
    if (!mounted) return;
    setState(() {
      _songs = filtered;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final player = PlayerService.instance;
    final songs = _songs;
    final representative = songs.isNotEmpty ? songs.first : null;
    final artistLabel = representative != null
        ? primaryArtistLabel(representative.artist)
        : '未知艺术家';
    final year = albumYearFromSongs(songs);
    final songCountText = '${songs.length}首';
    final infoText = year.isEmpty ? songCountText : '$songCountText · $year';

    final Set<String> participatingArtists = {};
    for (final song in songs) {
      participatingArtists.addAll(splitArtists(song.artist));
    }
    final sortedArtists = participatingArtists.toList()
      ..sort((a, b) => pinyinKey(a).compareTo(pinyinKey(b)));

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      useSafeArea: false,
      appBar: AppTopBar(
        title: widget.albumName,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                bottom: 160,
              ),
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
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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
                          contentPadding:
                              const EdgeInsets.only(left: 16, right: 16),
                          onTap: () async {
                            await player.playQueue(songs, index);
                          },
                          onLongPress: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (_) => SongDetailSheet(
                                song: song,
                                onOpenArtist: (artistName) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ArtistDetailPage(
                                        artistName: artistName,
                                      ),
                                    ),
                                  );
                                },
                                onOpenAlbum: (albumName) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AlbumDetailPage(
                                        albumName: albumName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
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
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                          placeholder:
                              CircleAvatar(radius: 22, child: Text(initial)),
                        ),
                        title: Text(artist),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtistDetailPage(artistName: artist),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                  const SizedBox(height: 24),
              ],
            ),
      bottomNavIndex: null,
      onBottomNavTap: null,
    );
  }
}

class _AlbumGroup {
  final String name;
  final List<SongEntity> songs;

  const _AlbumGroup({
    required this.name,
    required this.songs,
  });
}

class ArtworkWidget extends StatefulWidget {
  final SongEntity song;
  final double size;
  final double borderRadius;
  final Widget? placeholder;

  const ArtworkWidget({
    super.key,
    required this.song,
    required this.size,
    required this.borderRadius,
    this.placeholder,
  });

  @override
  State<ArtworkWidget> createState() => _ArtworkWidgetState();
}

class _ArtworkWidgetState extends State<ArtworkWidget> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tryLoad();
  }

  @override
  void didUpdateWidget(covariant ArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _bytes = null;
      _loading = false;
      _tryLoad();
    }
  }

  Future<void> _tryLoad() async {
    final cachedPath = widget.song.localCoverPath;
    if (cachedPath != null && cachedPath.trim().isNotEmpty) {
      final file = File(cachedPath);
      if (await file.exists()) {
        setState(() {
          _loading = false;
        });
        return;
      }
    }
    if (!widget.song.isLocal) return;
    final uri = widget.song.uri;
    if (uri == null || uri.isEmpty) return;
    setState(() => _loading = true);
    final bytes = await compute(_readArtworkBytes, uri);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cachedPath = widget.song.localCoverPath;
    final placeholder = widget.placeholder ??
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );

    Widget child;
    if (cachedPath != null && cachedPath.trim().isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.file(
          File(cachedPath),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    } else if (_bytes != null && _bytes!.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    } else if (_loading) {
      child = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: SizedBox(
            width: widget.size * 0.35,
            height: widget.size * 0.35,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      child = placeholder;
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: child,
    );
  }
}

Future<Uint8List?> _readArtworkBytes(String uri) async {
  try {
    final file = File(uri);
    if (!await file.exists()) return null;
    final metadata = readMetadata(file, getImage: true);
    if (metadata.pictures.isEmpty) return null;
    final bytes = metadata.pictures.first.bytes;
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

