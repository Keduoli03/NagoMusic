import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/state/song_state.dart';

class PlayerHeader extends StatelessWidget {
  final ValueListenable<SongEntity?> songListenable;

  const PlayerHeader({super.key, required this.songListenable});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = scheme.onSurface;
    final subtitleColor = scheme.onSurfaceVariant.withValues(alpha: 0.8);

    return ValueListenableBuilder<SongEntity?>(
      valueListenable: songListenable,
      builder: (context, song, child) {
        final title = song?.title ?? '未知歌曲';
        final artist = song?.artist ?? '未知歌手';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

