import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../app/state/song_state.dart';

class ArtworkWidget extends StatefulWidget {
  final SongEntity song;
  final double size;
  final double borderRadius;
  final Widget? placeholder;
  final bool preferOriginal;

  const ArtworkWidget({
    super.key,
    required this.song,
    required this.size,
    required this.borderRadius,
    this.placeholder,
    this.preferOriginal = false,
  });

  @override
  State<ArtworkWidget> createState() => _ArtworkWidgetState();
}

class _ArtworkWidgetState extends State<ArtworkWidget> with SignalsMixin {
  static const _maxCache = 100;
  static const _maxConcurrent = 12;
  static final _bytesCache = <String, Uint8List?>{};
  static final _loadingFutures = <String, Future<Uint8List?>>{};
  static final _queue = <_ArtworkTask>[];
  static int _active = 0;

  late final _bytes = createSignal<Uint8List?>(null);
  late final _loading = createSignal(false);

  @override
  void initState() {
    super.initState();
    _tryLoad();
  }

  @override
  void didUpdateWidget(covariant ArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _bytes.value = null;
      _loading.value = false;
      _tryLoad();
    }
  }

  Future<void> _tryLoad() async {
    final cachedPath = widget.song.localCoverPath;
    if (!widget.preferOriginal &&
        cachedPath != null &&
        cachedPath.trim().isNotEmpty) {
      final file = File(cachedPath);
      if (await file.exists()) {
        _loading.value = false;
        return;
      }
    }
    if (!widget.song.isLocal) return;
    final uri = widget.song.uri;
    if (uri == null || uri.isEmpty) return;
    final cacheKey = widget.preferOriginal ? '$uri|original' : uri;
    if (_bytesCache.containsKey(cacheKey)) {
      final cached = _bytesCache[cacheKey];
      // Move to end (LRU)
      _bytesCache.remove(cacheKey);
      _bytesCache[cacheKey] = cached;
      
      if (cached != null && cached.isNotEmpty) {
        _bytes.value = cached;
      }
      _loading.value = false;
      return;
    }
    final inflight = _loadingFutures[cacheKey];
    if (inflight != null) {
      _loading.value = true;
      final bytes = await inflight;
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        _bytes.value = bytes;
      }
      _loading.value = false;
      return;
    }
    _loading.value = true;
    final completer = Completer<Uint8List?>();
    _loadingFutures[cacheKey] = completer.future;
    _queue.add(_ArtworkTask(uri, cacheKey, widget.preferOriginal, completer));
    _drainQueue();
    final bytes = await completer.future.whenComplete(() {
      _loadingFutures.remove(cacheKey);
    });
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      _bytes.value = bytes;
    }
    _loading.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cachedPath = widget.song.localCoverPath;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheSize = (widget.size * dpr).round();
    final cacheWidth =
        widget.preferOriginal ? null : (cacheSize > 0 ? cacheSize : null);
    final cacheHeight = cacheWidth;
    final placeholder = widget.placeholder ??
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );

    return Watch.builder(
      builder: (context) {
        Widget child;
        final bytes = _bytes.value;
        final isLoading = _loading.value;
        if (widget.preferOriginal && bytes != null && bytes.isNotEmpty) {
          child = ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          );
        } else if (cachedPath != null && cachedPath.trim().isNotEmpty) {
          child = ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Image.file(
              File(cachedPath),
              width: widget.size,
              height: widget.size,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          );
        } else if (bytes != null && bytes.isNotEmpty) {
          child = ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
          );
        } else if (isLoading) {
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
      },
    );
  }
}

class _ArtworkTask {
  final String uri;
  final String cacheKey;
  final bool preferOriginal;
  final Completer<Uint8List?> completer;

  _ArtworkTask(this.uri, this.cacheKey, this.preferOriginal, this.completer);
}

void _drainQueue() {
  while (_ArtworkWidgetState._active < _ArtworkWidgetState._maxConcurrent &&
      _ArtworkWidgetState._queue.isNotEmpty) {
    // Use LIFO (Last-In-First-Out) strategy to prioritize currently visible items
    final task = _ArtworkWidgetState._queue.removeLast();
    _ArtworkWidgetState._active += 1;
    _readArtworkBytes(task.uri)
        .then((bytes) async {
          if (bytes != null &&
              bytes.isNotEmpty &&
              !task.preferOriginal) {
            try {
              final compressed = await FlutterImageCompress.compressWithList(
                bytes,
                minWidth: 300,
                minHeight: 300,
                quality: 85,
              );
              if (compressed.isNotEmpty) {
                bytes = compressed;
              }
            } catch (_) {}
          }

          if (!task.completer.isCompleted) {
            task.completer.complete(bytes);
          }
          if (bytes != null) {
            _ArtworkWidgetState._bytesCache.remove(task.cacheKey);
            _ArtworkWidgetState._bytesCache[task.cacheKey] = bytes;
            if (_ArtworkWidgetState._bytesCache.length >
                _ArtworkWidgetState._maxCache) {
              _ArtworkWidgetState._bytesCache
                  .remove(_ArtworkWidgetState._bytesCache.keys.first);
            }
          } else {
            _ArtworkWidgetState._bytesCache.putIfAbsent(
              task.cacheKey,
              () => null,
            );
          }
        })
        .catchError((_) {
          if (!task.completer.isCompleted) {
            task.completer.complete(null);
          }
          _ArtworkWidgetState._bytesCache.putIfAbsent(
            task.cacheKey,
            () => null,
          );
        })
        .whenComplete(() {
          _ArtworkWidgetState._active -= 1;
          _drainQueue();
        });
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
