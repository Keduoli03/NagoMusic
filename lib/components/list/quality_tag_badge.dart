import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/audio_quality.dart';

/// Small pill shown next to a song title indicating its audio quality tier
/// (Hi-Res / 无损 / HQ).
///
/// Reacts to [SongListDisplaySettings.showQualityTag]; renders nothing when the
/// setting is off or the song has no notable quality tier.
class QualityTagBadge extends StatelessWidget {
  final SongEntity song;

  const QualityTagBadge({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SongListDisplaySettings.showQualityTag,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        final tag = audioQualityTagFor(song);
        if (tag == null) return const SizedBox.shrink();
        final color = tag.color(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Text(
            tag.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        );
      },
    );
  }
}
