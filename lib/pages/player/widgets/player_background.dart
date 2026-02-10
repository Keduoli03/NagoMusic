import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';

class PlayerBackground extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const PlayerBackground({super.key, required this.songSignal});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
        final coverPath = song?.localCoverPath;
        final hasCover = coverPath != null && coverPath.isNotEmpty;
        return Stack(
          children: [
            if (hasCover)
              Positioned.fill(
                child: Image.file(
                  File(coverPath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) {
                    return _FallbackBackground(color: scheme.surface);
                  },
                ),
              )
            else
              _FallbackBackground(color: scheme.surface),
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  color: scheme.surface.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FallbackBackground extends StatelessWidget {
  final Color color;

  const _FallbackBackground({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.75),
            color.withValues(alpha: 0.85),
          ],
        ),
      ),
    );
  }
}
