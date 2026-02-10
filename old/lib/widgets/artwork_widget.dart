import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/storage/storage_keys.dart';
import '../core/storage/storage_util.dart';
import '../models/music_entity.dart';
import '../services/tag_probe_service.dart';

class ArtworkWidget extends StatefulWidget {
  final MusicEntity song;
  final double size;
  final double borderRadius;
  final Widget? placeholder;
  final Uint8List? artwork;

  const ArtworkWidget({
    super.key,
    required this.song,
    this.size = 48,
    this.borderRadius = 6,
    this.placeholder,
    this.artwork,
  });

  static void prefetchAround(
    List<MusicEntity> songs,
    int center, {
    int radius = 8,
  }) {
    _ArtworkWidgetState.prefetchAround(songs, center, radius: radius);
  }

  static Future<void> prefetchAll(List<MusicEntity> songs) async {
    _ArtworkWidgetState.prefetchAll(songs);
  }

  @override
  State<ArtworkWidget> createState() => _ArtworkWidgetState();
}

class _ArtworkWidgetState extends State<ArtworkWidget> {
  static final ListQueue<MusicEntity> _prefetchQueue = ListQueue();
  static final Set<String> _queuedIds = {};
  static int _inFlight = 0;
  Uint8List? _resolved;
  
  static int _prefetchConcurrency() {
    final stored = StorageUtil.getIntOrDefault(
      StorageKeys.artworkPrefetchConcurrency,
      defaultValue: 8,
    );
    return stored < 1 ? 1 : stored;
  }

  static void prefetchAround(
    List<MusicEntity> songs,
    int center, {
    int radius = 8,
  }) {
    if (songs.isEmpty) return;
    final start = center - radius < 0 ? 0 : center - radius;
    final end = center + radius >= songs.length ? songs.length - 1 : center + radius;
    for (var i = start; i <= end; i++) {
      _enqueueSong(songs[i]);
    }
    _drainQueue();
  }

  static Future<void> prefetchAll(List<MusicEntity> songs) async {
    if (songs.isEmpty) return;
    const int batchSize = 200;
    for (var i = 0; i < songs.length; i += batchSize) {
      final end = (i + batchSize < songs.length) ? i + batchSize : songs.length;
      for (var j = i; j < end; j++) {
        _enqueueSong(songs[j]);
      }
      _drainQueue();
      if (end < songs.length) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  static void _enqueueSong(MusicEntity song) {
    final id = song.id;
    if (song.artwork != null && song.artwork!.isNotEmpty) {
      // Already has artwork, ensure it's in cache if needed, but TagProbeService handles it
      return;
    }
    if (TagProbeService.getCachedArtwork(id) != null) return;
    if (_queuedIds.contains(id)) return;
    _queuedIds.add(id);
    _prefetchQueue.add(song);
  }

  static void _drainQueue() {
    if (_prefetchQueue.isEmpty) return;
    final maxConcurrent = _prefetchConcurrency();
    while (_inFlight < maxConcurrent && _prefetchQueue.isNotEmpty) {
      final song = _prefetchQueue.removeFirst();
      _queuedIds.remove(song.id);
      _inFlight += 1;
      _loadArtworkBytes(song).whenComplete(() {
        _inFlight -= 1;
        _drainQueue();
      });
    }
  }

  static Future<Uint8List?> _loadArtworkBytes(MusicEntity song) {
    return TagProbeService.loadArtwork(song);
  }

  @override
  void initState() {
    super.initState();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant ArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.artwork != widget.artwork ||
        oldWidget.song.artwork != widget.song.artwork ||
        oldWidget.song.localCoverPath != widget.song.localCoverPath) {
      _resolveArtwork();
    }
  }

  void _resolveArtwork() {
    final overrideArtwork = widget.artwork;
    if (overrideArtwork != null && overrideArtwork.isNotEmpty) {
      _resolved = overrideArtwork;
      return;
    }
    final inSong = widget.song.artwork;
    if (inSong != null && inSong.isNotEmpty) {
      _resolved = inSong;
      return;
    }
    final cached = TagProbeService.getCachedArtwork(widget.song.id);
    if (cached != null && cached.isNotEmpty) {
      _resolved = cached;
      return;
    }
    
    final localPath = widget.song.localCoverPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        // We still want to load it into memory eventually for fast scrolling reuse
        // but for now, we can let Image.file handle it if not cached.
        // However, TagProbeService.loadArtwork will put it in cache.
        _resolved = null;
        _loadArtworkAsync();
        return;
      }
    }
    
    _resolved = null;
    _loadArtworkAsync();
  }

  void _loadArtworkAsync() {
    _loadArtworkBytes(widget.song).then((bytes) {
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _resolved = bytes;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (resolved != null && resolved.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.memory(
          resolved,
          width: widget.size,
          height: widget.size,
          cacheWidth: (widget.size * MediaQuery.of(context).devicePixelRatio).toInt(),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      );
    }

    final localPath = widget.song.localCoverPath;
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Image.file(
            file,
            width: widget.size,
            height: widget.size,
            cacheWidth: (widget.size * 2).toInt(),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
          ),
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    if (widget.placeholder != null) return widget.placeholder!;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Icon(
        Icons.music_note,
        size: widget.size * 0.6,
        color: Colors.white24,
      ),
    );
  }
}
