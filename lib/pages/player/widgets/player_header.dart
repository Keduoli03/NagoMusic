import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';

class PlayerHeader extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const PlayerHeader({super.key, required this.songSignal});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = scheme.onSurface;
    final subtitleColor = scheme.onSurfaceVariant.withValues(alpha: 0.8);

    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
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
