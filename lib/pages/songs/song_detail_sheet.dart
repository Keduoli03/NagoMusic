import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/artwork_cache_helper.dart';
import '../../app/services/cache/audio_cache_service.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/metadata/tag_probe_service.dart';
import '../../app/services/metadata/tag_probe_result.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/common/app_list_tile.dart';
import '../../components/common/sheet_panels.dart';
import '../../components/feedback/app_toast.dart';
import '../library/playlists_page.dart';

class SongDetailSheet extends StatefulWidget {
  final SongEntity song;
  final ValueChanged<SongEntity>? onUpdated;
  final ValueChanged<String>? onDeleted;
  final ValueChanged<String>? onOpenArtist;
  final ValueChanged<String>? onOpenAlbum;

  const SongDetailSheet({
    super.key,
    required this.song,
    this.onUpdated,
    this.onDeleted,
    this.onOpenArtist,
    this.onOpenAlbum,
  });

  static List<String> splitArtists(String raw) {
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

  static String primaryArtistName(String rawArtist) {
    final list = splitArtists(rawArtist);
    if (list.isEmpty) return '未知艺术家';
    if (list.length == 1) return list.first;
    return list.first;
  }

  @override
  State<SongDetailSheet> createState() => _SongDetailSheetState();
}

class _SongDetailSheetState extends State<SongDetailSheet> {
  final PlaylistsService _playlists = PlaylistsService.instance;
  bool _isFavorite = false;
  bool _loadingFavorite = true;
  String _favoriteName = PlaylistsService.favoritePlaylistName;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    final songId = widget.song.id;
    final list = await _playlists.loadAll();
    PlaylistEntity? favorite;
    for (final p in list) {
      if (p.isFavorite || p.id == PlaylistsService.favoritePlaylistId) {
        favorite = p;
        break;
      }
    }
    final next = favorite?.songIds.contains(songId) ?? false;
    final name = (favorite?.name ?? '').trim();
    if (!mounted) return;
    setState(() {
      _isFavorite = next;
      _loadingFavorite = false;
      if (name.isNotEmpty) {
        _favoriteName = name;
      }
    });
  }

  Future<void> _toggleFavorite() async {
    if (_loadingFavorite) return;
    final songId = widget.song.id;
    if (_isFavorite) {
      await _playlists.removeSongs(
        PlaylistsService.favoritePlaylistId,
        [songId],
      );
      if (!mounted) return;
      setState(() => _isFavorite = false);
      AppToast.show(context, '已从$_favoriteName移出');
    } else {
      await _playlists.addSongs(
        PlaylistsService.favoritePlaylistId,
        [songId],
      );
      if (!mounted) return;
      setState(() => _isFavorite = true);
      AppToast.show(context, '已添加到$_favoriteName');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.scaffoldBackgroundColor;
    final secondaryTextColor =
        isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100);
    final song = widget.song;
    final album = (song.album ?? '').trim();
    final rawArtist = song.artist.trim();
    final artist = rawArtist.isEmpty ? '未知艺术家' : rawArtist;
    final primaryArtist = SongDetailSheet.primaryArtistName(artist);
    final canOpenAlbum = album.isNotEmpty && album != '未知专辑';
    final coverPath = (song.localCoverPath ?? '').trim();
    final hasCover = coverPath.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: hasCover
                        ? Image.file(
                            File(coverPath),
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _coverPlaceholder(theme, song.title);
                            },
                          )
                        : _coverPlaceholder(theme, song.title),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _MarqueeText(
                          '$artist${album.isNotEmpty ? ' · $album' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _isFavorite ? theme.colorScheme.error : null,
                    ),
                    onPressed: _loadingFavorite ? null : _toggleFavorite,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.6),
            AppListTile(
              leading: const Icon(Icons.queue_play_next),
              title: '下一首播放',
              onTap: () async {
                await PlayerService.instance.playNext(song);
                if (!context.mounted) return;
                AppToast.show(context, '已添加到下一首');
                Navigator.of(context).pop();
              },
            ),
            AppListTile(
              leading: const Icon(Icons.add_to_photos_outlined),
              title: '添加到歌单',
              onTap: () async {
                await showAddToPlaylistDialog(
                  context,
                  songIds: [song.id],
                );
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
            AppListTile(
              leading: const Icon(Icons.person),
              title: '艺术家：$primaryArtist',
              onTap: () {
                final nav = Navigator.of(context);
                nav.pop();
                widget.onOpenArtist?.call(primaryArtist);
              },
            ),
            if (canOpenAlbum)
              AppListTile(
                leading: const Icon(Icons.album),
                title: '专辑：$album',
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                widget.onOpenAlbum?.call(album);
                },
              ),
            AppListTile(
              leading: const Icon(Icons.info_outline),
              title: '歌曲信息',
              onTap: () {
                final nav = Navigator.of(context);
                nav.pop();
                showModalBottomSheet<void>(
                  context: nav.context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => SongInfoSheet(song: song),
                );
              },
            ),
            AppListTile(
              leading: const Icon(Icons.refresh),
              title: '刮削信息',
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop();
                final updated = await showModalBottomSheet<SongEntity>(
                  context: nav.context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => SongScrapeSheet(song: song),
                );
                if (updated != null) {
                  widget.onUpdated?.call(updated);
                }
              },
            ),
            AppListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: '移除歌曲',
              titleColor: Colors.red,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('移除歌曲'),
                      content: const Text('确定要将这首歌曲从媒体库中移除吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('移除'),
                        ),
                      ],
                    );
                  },
                );
                if (ok != true) return;
                final removed = await SongDao().deleteByIds([song.id]);
                if (!context.mounted) return;
                if (removed > 0) {
                  await PlayerService.instance.removeSongsById([song.id]);
                  if (!context.mounted) return;
                  if (coverPath.isNotEmpty) {
                    await ArtworkCacheHelper.removeCachedArtworkByPath(coverPath);
                  }
                  await ArtworkCacheHelper.removeCachedArtwork(key: song.id);
                  await LyricsRepository().removeCachedLrc(song.id);
                  final uri = (song.uri ?? '').trim();
                  if (!song.isLocal && uri.startsWith('http')) {
                    Map<String, String>? headers;
                    final raw = (song.headersJson ?? '').trim();
                    if (raw.isNotEmpty) {
                      try {
                        final decoded = jsonDecode(raw);
                        if (decoded is Map) {
                          headers = decoded.map(
                            (key, value) =>
                                MapEntry(key.toString(), value.toString()),
                          );
                        }
                      } catch (_) {}
                    }
                    await AudioCacheService.instance.removeCachedFiles(
                      uri: uri,
                      headers: headers,
                    );
                    await TagProbeService.instance.removeRemoteProbeCache(
                      uri: uri,
                      headers: headers,
                    );
                  }
                  widget.onDeleted?.call(song.id);
                  if (!context.mounted) return;
                  AppToast.show(context, '已移除');
                  Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(ThemeData theme, String title) {
    final letter = title.trim().isEmpty ? '?' : title.trim().substring(0, 1);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText(
    this.text, {
    this.style,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  static const double _velocity = 30.0;
  static const double _blankSpace = 40.0;
  late final ScrollController _scrollController;
  late final Ticker _ticker;
  double _textWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (!_scrollController.hasClients) return;
    final cycleLength = _textWidth + _blankSpace;
    if (cycleLength <= 0) return;
    final pixels = (elapsed.inMilliseconds / 1000.0) * _velocity;
    final raw = pixels % cycleLength;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    _scrollController.jumpTo(raw.clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: textStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    _textWidth = textPainter.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldScroll = _textWidth > constraints.maxWidth;
        if (!shouldScroll) {
          if (_ticker.isActive) _ticker.stop();
          return Text(
            widget.text,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        if (!_ticker.isActive) _ticker.start();
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Text(widget.text, style: textStyle),
              const SizedBox(width: _blankSpace),
              Text(widget.text, style: textStyle),
              const SizedBox(width: _blankSpace),
            ],
          ),
        );
      },
    );
  }
}

class SongInfoSheet extends StatelessWidget {
  final SongEntity song;

  const SongInfoSheet({super.key, required this.song});

  String _durationText(int? ms) {
    final v = ms ?? 0;
    if (v <= 0) return '--:--';
    final total = (v / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int? bytes) {
    final v = bytes ?? 0;
    if (v <= 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = v.toDouble();
    var idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    final fixed = size < 10 && idx > 0 ? 2 : 1;
    return '${size.toStringAsFixed(fixed)} ${units[idx]}';
  }

  String _formatBitrate(int? bitrate) {
    final v = bitrate ?? 0;
    if (v <= 0) return '-';
    final kbps = v / 1000;
    final fixed = kbps >= 100 ? 0 : 1;
    return '${kbps.toStringAsFixed(fixed)} kbps';
  }

  String _formatSampleRate(int? sampleRate) {
    final v = sampleRate ?? 0;
    if (v <= 0) return '-';
    if (v < 1000) return '$v Hz';
    final khz = v / 1000;
    final fixed = khz >= 100 ? 0 : 1;
    return '${khz.toStringAsFixed(fixed)} kHz';
  }

  Future<String> _resolveSourceName() async {
    if (song.isLocal) return '本地音乐';
    final id = (song.sourceId ?? '').trim();
    if (id.isEmpty) return '-';
    final sources = await WebDavSourceRepository.instance.loadSources();
    final matched =
        sources.cast<WebDavSource?>().firstWhere((s) => s?.id == id, orElse: () => null);
    final name = (matched?.name ?? '').trim();
    return name.isNotEmpty ? name : id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.brightness == Brightness.dark
        ? Colors.white70
        : const Color.fromARGB(255, 100, 100, 100);

    Widget row(String k, String v) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                k,
                style: TextStyle(color: secondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    String fmtStr(String? v) => (v ?? '').trim().isEmpty ? '-' : v!.trim();

    return AppSheetPanel(
      title: '歌曲信息',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('标题', song.title),
          row('艺术家', song.artist),
          row('专辑', song.album ?? '-'),
          row('时长', _durationText(song.durationMs)),
          row('码率', _formatBitrate(song.bitrate)),
          row('采样率', _formatSampleRate(song.sampleRate)),
          row('大小', _formatFileSize(song.fileSize)),
          row('格式', fmtStr(song.format)),
          FutureBuilder<String>(
            future: _resolveSourceName(),
            builder: (context, snapshot) {
              final v = snapshot.data;
              return row('音源', fmtStr(v ?? song.sourceId));
            },
          ),
          row('URI', fmtStr(song.uri)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class SongScrapeSheet extends StatefulWidget {
  final SongEntity song;

  const SongScrapeSheet({super.key, required this.song});

  @override
  State<SongScrapeSheet> createState() => _SongScrapeSheetState();
}

class _SongScrapeSheetState extends State<SongScrapeSheet>
    with SignalsMixin {
  final SongDao _dao = SongDao();
  final LyricsRepository _lyrics = LyricsRepository();
  late final _working = createSignal(false);
  late final _force = createSignal(false);
  late final _lastResult = createSignal<TagProbeResult?>(null);
  late final _lastError = createSignal<String?>(null);

  SongEntity get _song => widget.song;
  bool get _isLocal => _song.isLocal;

  Map<String, String>? _headers() {
    if (_song.isLocal) return null;
    final raw = (_song.headersJson ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearScrapeInfo() async {
    final coverPath = (_song.localCoverPath ?? '').trim();
    if (coverPath.isNotEmpty) {
      try {
        final file = File(coverPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await _lyrics.removeCachedLrc(_song.id);
    final uri = (_song.uri ?? '').trim();
    if (!_song.isLocal && uri.isNotEmpty) {
      await TagProbeService.instance.clearRemoteCaches(
        uri: uri,
        headers: _headers(),
      );
    }
    final cleared = SongEntity(
      id: _song.id,
      title: _song.title,
      artist: _song.artist,
      album: _song.album,
      uri: _song.uri,
      isLocal: _song.isLocal,
      headersJson: _song.headersJson,
      durationMs: null,
      bitrate: null,
      sampleRate: null,
      fileSize: null,
      format: null,
      sourceId: _song.sourceId,
      fileModifiedMs: _song.fileModifiedMs,
      localCoverPath: null,
      tagsParsed: false,
    );
    await _dao.upsertSongs([cleared]);
    if (!mounted) return;
    AppToast.show(context, '已清除');
    Navigator.pop(context, cleared);
  }

  Future<void> _scrape() async {
    if (_working.value) return;
    final uri = (_song.uri ?? '').trim();
    if (uri.isEmpty) {
      AppToast.show(context, '无效 URI');
      return;
    }
    _working.value = true;
    _lastError.value = null;
    try {
      if (!_isLocal && _force.value) {
        await TagProbeService.instance.clearRemoteCaches(
          uri: uri,
          headers: _headers(),
        );
      }
      final result = _isLocal
          ? await TagProbeService.instance.probeSong(
              uri: uri,
              isLocal: true,
              includeArtwork: true,
            )
          : (_force.value
              ? await TagProbeService.instance.probeSong(
                  uri: uri,
                  isLocal: false,
                  headers: _headers(),
                  includeArtwork: true,
                )
              : await TagProbeService.instance.probeSongDedup(
                  uri: uri,
                  isLocal: false,
                  headers: _headers(),
                  includeArtwork: true,
                ));
      if (result == null) {
        if (!mounted) return;
        _lastResult.value = null;
        _lastError.value = '未找到可用标签';
        AppToast.show(context, '没找到', type: ToastType.info);
        return;
      }

      String? coverPath = _song.localCoverPath;
      final artwork = result.artwork;
      if (artwork != null && artwork.isNotEmpty) {
        final cached = await ArtworkCacheHelper.cacheCompressedArtwork(
          bytes: artwork,
          key: _song.id,
        );
        if (cached != null && cached.isNotEmpty) {
          coverPath = cached;
        }
      }

      final lyrics = (result.lyrics ?? '').trim();
      if (lyrics.isNotEmpty) {
        await _lyrics.saveLrcToCache(
          _song.id,
          lyrics,
          overwrite: _isLocal ? true : _force.value,
        );
      }

      final updated = SongEntity(
        id: _song.id,
        title: (result.title ?? '').trim().isNotEmpty
            ? result.title!.trim()
            : _song.title,
        artist: (result.artist ?? '').trim().isNotEmpty
            ? result.artist!.trim()
            : _song.artist,
        album: (result.album ?? '').trim().isNotEmpty
            ? result.album!.trim()
            : _song.album,
        uri: _song.uri,
        isLocal: _song.isLocal,
        headersJson: _song.headersJson,
        durationMs: result.durationMs ?? _song.durationMs,
        bitrate: result.bitrate ?? _song.bitrate,
        sampleRate: result.sampleRate ?? _song.sampleRate,
        fileSize: result.fileSize ?? _song.fileSize,
        format: result.format ?? _song.format,
        sourceId: _song.sourceId,
        fileModifiedMs: _song.fileModifiedMs,
        localCoverPath: coverPath,
        tagsParsed: true,
      );
      await _dao.upsertSongs([updated]);
      if (!mounted) return;
      _lastResult.value = result;
      AppToast.show(context, '已更新', type: ToastType.success);
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      _lastError.value = '刮削失败';
      AppToast.show(context, '刮削失败');
    } finally {
      if (mounted) {
        _working.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final theme = Theme.of(context);
        final secondary = theme.brightness == Brightness.dark
            ? Colors.white70
            : const Color.fromARGB(255, 100, 100, 100);
        final hasCover = (_song.localCoverPath ?? '').trim().isNotEmpty;

        return FutureBuilder<bool>(
          future: _lyrics.hasCachedLrc(_song.id),
          builder: (context, snap) {
            final hasLyrics = snap.data == true;
            final last = _lastResult.value;
            final lastError = _lastError.value;
            final isWorking = _working.value;

            Widget statusRow(String k, String v) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        k,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(v, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              );
            }

            return AppSheetPanel(
              title: '刮削信息',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  statusRow('标签已解析', _song.tagsParsed ? '是' : '否'),
                  statusRow('封面缓存', hasCover ? '有' : '无'),
                  statusRow('歌词缓存', hasLyrics ? '有' : '无'),
                  statusRow(
                    '时长',
                    (_song.durationMs ?? 0) > 0 ? '${_song.durationMs}ms' : '-',
                  ),
                  if (lastError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        lastError,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (last != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '最近一次结果',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          statusRow(
                            '标题',
                            (last.title ?? '-').trim().isEmpty
                                ? '-'
                                : last.title!.trim(),
                          ),
                          statusRow(
                            '艺术家',
                            (last.artist ?? '-').trim().isEmpty
                                ? '-'
                                : last.artist!.trim(),
                          ),
                          statusRow(
                            '专辑',
                            (last.album ?? '-').trim().isEmpty
                                ? '-'
                                : last.album!.trim(),
                          ),
                          statusRow(
                            '封面',
                            (last.artwork?.isNotEmpty ?? false) ? '有' : '无',
                          ),
                          statusRow(
                            '歌词',
                            (last.lyrics ?? '').trim().isNotEmpty ? '有' : '无',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isWorking ? null : _clearScrapeInfo,
                            child: const Text('清除'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isWorking ? null : _scrape,
                            child: isWorking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    _isLocal
                                        ? '刮削'
                                        : (_force.value ? '刮削(强制)' : '刮削(智能)'),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isLocal)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('强制刮削'),
                        subtitle: const Text('忽略缓存，重新读取内置标签'),
                        value: _force.value,
                        onChanged: isWorking
                            ? null
                            : (v) => _force.value = v,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

