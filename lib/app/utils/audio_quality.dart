import 'package:flutter/material.dart';

import '../state/song_state.dart';

/// The quality tier a song falls into, derived from its technical metadata.
enum AudioQualityTier { hires, lossless, hq }

/// A display label + tier for a song's audio quality, shown as a badge in song
/// lists. Build one via [audioQualityTagFor].
class AudioQualityTag {
  final AudioQualityTier tier;
  final String label;

  const AudioQualityTag(this.tier, this.label);

  /// Accent color used for the badge text/border, resolved against the theme.
  Color color(BuildContext context) {
    switch (tier) {
      case AudioQualityTier.hires:
        // Gold — the premium tier, distinct from the theme accent.
        return const Color(0xFFC9971B);
      case AudioQualityTier.lossless:
        return Theme.of(context).colorScheme.primary;
      case AudioQualityTier.hq:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}

// Containers that carry lossless (PCM or losslessly-compressed) audio.
const Set<String> _losslessFormats = {
  'FLAC',
  'ALAC',
  'APE',
  'WAV',
  'WAVE',
  'WV',
  'AIFF',
  'AIF',
  'TAK',
  'TTA',
};

// One-bit DSD containers — always treated as Hi-Res.
const Set<String> _dsdFormats = {'DSF', 'DFF'};

/// Classifies [song] into a display tier, or returns null when it's standard
/// quality (or lacks the metadata needed to tell). [SongEntity.sampleRate] is
/// in Hz and [SongEntity.bitrate] in bits per second.
///
/// Note: `.m4a` is treated as lossy AAC, since the container is far more often
/// AAC than ALAC and the stored [SongEntity.format] can't disambiguate the two.
AudioQualityTag? audioQualityTagFor(SongEntity song) {
  final format = (song.format ?? '').trim().toUpperCase();
  final sampleRate = song.sampleRate ?? 0;
  final bitrate = song.bitrate ?? 0;

  if (_dsdFormats.contains(format)) {
    return const AudioQualityTag(AudioQualityTier.hires, 'Hi-Res');
  }
  if (_losslessFormats.contains(format)) {
    // Above CD quality (44.1/48 kHz) → Hi-Res; CD-quality lossless → 无损.
    if (sampleRate > 48000) {
      return const AudioQualityTag(AudioQualityTier.hires, 'Hi-Res');
    }
    return const AudioQualityTag(AudioQualityTier.lossless, '无损');
  }
  // Lossy containers: only flag the genuinely high-bitrate ones.
  if (bitrate >= 320000) {
    return const AudioQualityTag(AudioQualityTier.hq, 'HQ');
  }
  return null;
}
