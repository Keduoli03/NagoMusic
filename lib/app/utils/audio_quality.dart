import 'package:flutter/material.dart';

import '../state/song_state.dart';
import '../theme/app_colors.dart';

/// The quality tier a song falls into, derived from its technical metadata.
enum AudioQualityTier { hires, lossless, hq }

/// A display label + tier for a song's audio quality, shown as a badge in song
/// lists. Build one via [audioQualityTagFor].
class AudioQualityTag {
  final AudioQualityTier tier;
  final String label;

  const AudioQualityTag(this.tier, this.label);

  /// 徽章的文字与线框色 —— 三档各一个颜色，靠颜色而不是靠读字来区分。
  ///
  /// 都是压过饱和度的低调色：徽章会在列表里逐行出现，用高饱和色整屏会发花。
  /// 每档都分亮暗两套，单一色值在另一个主题下不是发闷就是刺眼。
  Color color(BuildContext context) {
    final isLight = AppColors.of(context).surface.computeLuminance() > 0.5;
    switch (tier) {
      case AudioQualityTier.hires:
        // 金
        return isLight ? const Color(0xFFB58A2B) : const Color(0xFFD9B45A);
      case AudioQualityTier.lossless:
        // 青蓝。刻意不用 colorScheme.primary —— 音质档位是客观规格，
        // 不该跟着用户选的主题色变，否则换个主题色就跟 Hi-Res 撞了。
        return isLight ? const Color(0xFF3D7D93) : const Color(0xFF7FB8CC);
      case AudioQualityTier.hq:
        // 中性灰：最低档，不需要被看见
        return AppColors.of(context).muted;
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
    return const AudioQualityTag(AudioQualityTier.hires, 'HI-RES');
  }
  if (_losslessFormats.contains(format)) {
    // Above CD quality (44.1/48 kHz) → Hi-Res; CD-quality lossless → 无损.
    if (sampleRate > 48000) {
      return const AudioQualityTag(AudioQualityTier.hires, 'HI-RES');
    }
    return const AudioQualityTag(AudioQualityTier.lossless, '无损');
  }
  // Lossy containers: only flag the genuinely high-bitrate ones.
  if (bitrate >= 320000) {
    return const AudioQualityTag(AudioQualityTier.hq, 'HQ');
  }
  return null;
}
