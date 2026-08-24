import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import '../../app/state/settings_state.dart';

/// Mini preview of the player UI for a given [PlayerStylePreset].
///
/// Used by the player-style picker (with its own gradient card background) and
/// by the 流光 settings preview (`fill: true`, transparent — sits over the real
/// dynamic background). [lyricsOnly] renders the lyrics-page mock instead of the
/// player, so the 流光 preview can show "player + lyrics" side by side.
class PlayerStylePreview extends StatelessWidget {
  final PlayerStylePreset preset;
  final bool selected;
  final bool fill;
  final bool lyricsOnly;

  static const String _sampleTitle = '逆光';
  static const String _sampleArtist = '孙燕姿';
  static const String sampleCoverAsset =
      'assets/preview/style_preview_cover.jpg';
  static const String _coverAsset = sampleCoverAsset;

  const PlayerStylePreview({
    super.key,
    required this.preset,
    this.selected = true,
    this.fill = false,
    this.lyricsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primary : scheme.secondary;
    final content = lyricsOnly
        ? _lyricsPage(context)
        : switch (preset) {
            PlayerStylePreset.classic => _classicPreview(context, accent),
            PlayerStylePreset.poster => _posterPreview(context, accent),
          };

    // Over the real 流光: no own background / aspect / clip (parent provides).
    if (fill) return content;

    final bg = Color.alphaBlend(
      accent.withValues(alpha: selected ? 0.20 : 0.12),
      scheme.surfaceContainerHighest,
    );
    final size = MediaQuery.sizeOf(context);
    final portraitRatio = size.shortestSide / size.longestSide;
    return AspectRatio(
      aspectRatio: portraitRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bg, scheme.surface.withValues(alpha: 0.78)],
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _lyricsPage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lyricLine(context, '不解释 低着头沉默', size: 8),
          const SizedBox(height: 10),
          _lyricLine(context, '我该相信你很爱我', size: 8),
          const SizedBox(height: 10),
          _lyricLine(context, '有一束光 那瞬间', size: 8),
          const SizedBox(height: 10),
          _lyricLine(context, '是什么痛得刺眼', active: true, size: 11),
          const SizedBox(height: 10),
          _lyricLine(context, '你的视线 是谅解', size: 8),
          const SizedBox(height: 10),
          _lyricLine(context, '为什么舍不得熄灭', size: 8),
        ],
      ),
    );
  }

  Widget _classicPreview(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                AppIcons.chevronDown,
                size: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              Icon(
                AppIcons.moreHorizontal,
                size: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _titleText(context, _sampleTitle, size: 9),
          const SizedBox(height: 2),
          _titleText(context, _sampleArtist, size: 7, secondary: true),
          const Spacer(),
          _cover(accent, size: 62, radius: 8),
          const Spacer(),
          _lyricLine(context, '是什么痛得刺眼', active: true, size: 8),
          const Spacer(),
          _progress(context, times: true),
          const SizedBox(height: 8),
          _controls(context, accent),
          const SizedBox(height: 8),
          _bottomActions(context),
        ],
      ),
    );
  }

  Widget _posterPreview(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _coverAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.92),
                        accent.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),
              // In fill mode let the cover meet the 流光 directly; otherwise fade
              // into the card's surface.
              if (!fill)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        scheme.surface.withValues(alpha: 0.55),
                        scheme.surface,
                      ],
                      stops: const [0.5, 0.85, 1],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 9, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleText(context, _sampleTitle, size: 11),
                const SizedBox(height: 2),
                _titleText(context, _sampleArtist, size: 7, secondary: true),
                const SizedBox(height: 8),
                _lyricLine(context, '有一束光 那瞬间', size: 7),
                const SizedBox(height: 5),
                _lyricLine(context, '是什么痛得刺眼', active: true, size: 9),
                const SizedBox(height: 5),
                _lyricLine(context, '你的视线 是谅解', size: 7),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      AppIcons.heart,
                      size: 13,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                    const Spacer(),
                    Icon(
                      AppIcons.menu,
                      size: 13,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _progress(context, times: true, accentTrack: false),
                const SizedBox(height: 8),
                _posterControls(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cover(Color color, {required double size, required double radius}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        _coverAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.92),
                color.withValues(alpha: 0.48),
              ],
            ),
          ),
          child: Icon(
            AppIcons.musicNote,
            size: size * 0.4,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _titleText(
    BuildContext context,
    String text, {
    required double size,
    bool centered = false,
    bool secondary = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.left,
      style: TextStyle(
        fontSize: size,
        height: 1.1,
        fontWeight: secondary ? FontWeight.w500 : FontWeight.w700,
        color: secondary
            ? scheme.onSurfaceVariant.withValues(alpha: 0.72)
            : scheme.onSurface,
      ),
    );
  }

  Widget _lyricLine(
    BuildContext context,
    String text, {
    bool active = false,
    required double size,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        height: 1.1,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active
            ? scheme.onSurface
            : scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _progress(
    BuildContext context, {
    bool thick = false,
    bool times = false,
    bool accentTrack = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final height = thick ? 3.0 : 2.5;
    final fillColor = accentTrack
        ? scheme.onSurface.withValues(alpha: 0.72)
        : scheme.onSurface.withValues(alpha: 0.6);
    final bar = Stack(
      alignment: Alignment.centerLeft,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        FractionallySizedBox(
          widthFactor: 0.4,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const FractionallySizedBox(
          widthFactor: 0.4,
          alignment: Alignment.centerLeft,
          child: Align(
            alignment: Alignment.centerRight,
            child: _ProgressThumb(),
          ),
        ),
      ],
    );
    if (!times) return bar;
    return Column(
      children: [
        bar,
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_timeText(context, '1:28'), _timeText(context, '4:29')],
        ),
      ],
    );
  }

  Widget _timeText(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 6.5,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _controls(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final sideColor = scheme.onSurface.withValues(alpha: 0.82);
    const mainSize = 24.0;
    const sideSize = 16.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Icon(AppIcons.skipPrevious, size: sideSize, color: sideColor),
        Container(
          width: mainSize,
          height: mainSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            AppIcons.play,
            size: mainSize * 0.62,
            color: scheme.onPrimaryContainer,
          ),
        ),
        Icon(AppIcons.skipNext, size: sideSize, color: sideColor),
      ],
    );
  }

  Widget _posterControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurface.withValues(alpha: 0.78);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(AppIcons.repeat, size: 12, color: color),
        Icon(AppIcons.skipPrevious, size: 16, color: color),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.onSurface,
          ),
          child: Icon(AppIcons.play, size: 15, color: scheme.surface),
        ),
        Icon(AppIcons.skipNext, size: 16, color: color),
        Icon(AppIcons.moreVertical, size: 12, color: color),
      ],
    );
  }

  Widget _bottomActions(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(AppIcons.repeat, size: 11, color: color),
        Icon(AppIcons.alarm, size: 11, color: color),
        Icon(AppIcons.list, size: 11, color: color),
        Icon(AppIcons.moreHorizontal, size: 11, color: color),
      ],
    );
  }
}

class _ProgressThumb extends StatelessWidget {
  const _ProgressThumb();

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(2, 0),
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
