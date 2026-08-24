import 'dart:ui';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter/material.dart';

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/router/app_router.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/state/song_state.dart';
import '../../common/artwork_widget.dart';
import '../../../pages/player/player_page.dart';
import '../../../pages/player/widgets/player_bottom_panel.dart';

class MiniPlayerBar extends StatelessWidget {
  static const double estimatedHeight = 70.0;

  final PlayerService player;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onOpenQueue;
  final EdgeInsetsGeometry padding;
  final double artworkSize;
  final double borderRadius;
  final List<BoxShadow>? boxShadow;
  final bool enableSwipe;
  final Widget? trailing;

  MiniPlayerBar({
    super.key,
    PlayerService? player,
    this.onOpenPlayer,
    this.onOpenQueue,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.artworkSize = 48,
    this.borderRadius = 20,
    this.boxShadow,
    this.enableSwipe = true,
    this.trailing,
  }) : player = player ?? PlayerService.instance;

  @override
  Widget build(BuildContext context) {
    // Only rebuild the bar chrome when the SONG changes — not on every position
    // tick. Position/playing are consumed by the leaf play-button & subtitle
    // widgets, which have their own snapshot listeners.
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: player.currentSong,
      builder: (context, song, child) {
        final hasSong = song != null;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final openPlayer =
            onOpenPlayer ??
            () {
              final isTabletLayout = AppLayoutSettings.tabletMode.value;
              final navigator = Navigator.of(
                context,
                rootNavigator: isTabletLayout,
              );
              navigator.push(_playerRoute());
            };
        final openQueue =
            onOpenQueue ?? () => showPlayerPlaylistSheet(context, player);

        final isDark = theme.brightness == Brightness.dark;
        // 必须是**不透明**的。以前浅色是 white@90%、深色是 surface@86%，结果是
        // 卡片下面那一行歌曲会整个透出来，看着像渲染没画完而不是「毛玻璃」。
        // mini player 是浮在内容之上的，浮层就该挡住底下的东西。
        final bgColor = isDark
            ? scheme.surfaceContainerHigh
            : Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.025),
                Colors.white,
              );

        final border = Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : scheme.outlineVariant.withValues(alpha: 0.42),
          width: 0.8,
        );

        final defaultShadow = [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ];

        final content = Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(borderRadius),
              onTap: openPlayer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: MiniPlayerArtwork(
                        song: song,
                        size: artworkSize,
                        borderRadius: 10,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: MiniPlayerInfo(
                        song: song,
                        enableSwipe: enableSwipe,
                        player: player,
                        onOpenPlayer: openPlayer,
                      ),
                    ),
                    const SizedBox(width: 6),
                    MiniPlayerPlayButton(
                      player: player,
                      size: 38,
                      enabled: hasSong,
                    ),
                    const SizedBox(width: 4),
                    trailing ??
                        MiniPlayerQueueButton(
                          onPressed: hasSong ? openQueue : null,
                          color: scheme.onSurface,
                        ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ),
          ),
        );

        return Padding(
          padding: padding,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: boxShadow ?? defaultShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: ValueListenableBuilder<bool>(
                valueListenable: AppBackgroundSettings.glassEffectEnabled,
                builder: (context, glassEnabled, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: AppBackgroundSettings.panelBlurStrength,
                    builder: (context, blurStrength, _) {
                      if (!glassEnabled || blurStrength <= 0) return content;
                      return BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurStrength,
                          sigmaY: blurStrength,
                        ),
                        child: content,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Route _playerRoute() {
    return PageRouteBuilder(
      settings: const RouteSettings(name: AppRoutes.player),
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const PlayerPage(),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final offset = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved);
        // Slight scale + fade so the player "lifts" into place rather than just
        // sliding up flatly.
        final scale = Tween<double>(begin: 0.97, end: 1.0).animate(curved);
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
        );
        return SlideTransition(
          position: offset,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class MiniPlayerArtwork extends StatelessWidget {
  final SongEntity? song;
  final double size;
  final double borderRadius;

  const MiniPlayerArtwork({
    super.key,
    required this.song,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (song == null) {
      return _ArtworkFallback(
        size: size,
        borderRadius: borderRadius,
        color: scheme.surfaceContainerHighest,
      );
    }
    return ArtworkWidget(
      song: song!,
      size: size,
      borderRadius: borderRadius,
      placeholder: _ArtworkFallback(
        size: size,
        borderRadius: borderRadius,
        color: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  final double size;
  final double borderRadius;
  final Color color;

  const _ArtworkFallback({
    required this.size,
    required this.borderRadius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(AppIcons.musicNote, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class MiniPlayerInfo extends StatelessWidget {
  final SongEntity? song;
  final bool enableSwipe;
  final PlayerService player;
  final VoidCallback onOpenPlayer;

  const MiniPlayerInfo({
    super.key,
    required this.song,
    required this.enableSwipe,
    required this.player,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    MiniPlayerInfoSettings.ensureLoaded();
    if (!enableSwipe) {
      return _InfoContent(
        song: song,
        player: player,
        onOpenPlayer: onOpenPlayer,
      );
    }
    return _SwipeableInfo(
      song: song,
      player: player,
      onOpenPlayer: onOpenPlayer,
    );
  }
}

class _InfoContent extends StatelessWidget {
  final SongEntity? song;
  final PlayerService player;
  final VoidCallback onOpenPlayer;

  const _InfoContent({
    required this.song,
    required this.player,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (song == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '未选择歌曲',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          song!.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        ValueListenableBuilder<bool>(
          valueListenable: MiniPlayerInfoSettings.showLyricsInSubtitle,
          builder: (context, showLyrics, _) {
            return ValueListenableBuilder<String?>(
              valueListenable: LyricsService.instance.currentLineText,
              builder: (context, currentLyric, _) {
                final lyric = currentLyric?.trim() ?? '';
                final subtitle = showLyrics && lyric.isNotEmpty
                    ? lyric
                    : song!.artist;
                return _MiniPlayerSubtitleText(
                  text: subtitle,
                  useProgressMarquee: showLyrics && lyric.isNotEmpty,
                  player: player,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _SwipeableInfo extends StatefulWidget {
  final SongEntity? song;
  final PlayerService player;
  final VoidCallback onOpenPlayer;

  const _SwipeableInfo({
    required this.song,
    required this.player,
    required this.onOpenPlayer,
  });

  @override
  State<_SwipeableInfo> createState() => _SwipeableInfoState();
}

class _SwipeableInfoState extends State<_SwipeableInfo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double>? _animation;
  double _dragOffsetX = 0;
  VoidCallback? _animationCompleted;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            final cb = _animationCompleted;
            _animationCompleted = null;
            _animation = null;
            if (cb != null) {
              cb();
            }
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runAnimation({
    required double begin,
    required double end,
    Curve curve = Curves.easeOut,
    Duration duration = const Duration(milliseconds: 200),
    VoidCallback? onCompleted,
  }) {
    _controller.duration = duration;
    _animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: curve));
    _animationCompleted = onCompleted;
    _controller.forward(from: 0);
  }

  void _animateBack() {
    final begin = _dragOffsetX;
    _runAnimation(
      begin: begin,
      end: 0,
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 260),
      onCompleted: () {
        if (mounted) {
          setState(() {
            _dragOffsetX = 0;
          });
        } else {
          _dragOffsetX = 0;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = widget.song != null;
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onOpenPlayer,
        onHorizontalDragUpdate: (details) {
          if (!hasSong) return;
          setState(() {
            final delta = details.primaryDelta ?? 0;
            _dragOffsetX = (_dragOffsetX + delta).clamp(-80.0, 80.0);
          });
        },
        onHorizontalDragEnd: (details) {
          if (!hasSong) {
            _animateBack();
            return;
          }
          final offset = _dragOffsetX;
          const threshold = 60.0;
          if (offset.abs() >= threshold) {
            if (offset < 0) {
              widget.player.next();
            } else {
              widget.player.previous();
            }
          }
          _animateBack();
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _animation != null
                  ? _animation!.value
                  : _dragOffsetX;
              return Transform.translate(
                offset: Offset(value, 0),
                child: child,
              );
            },
            child: _InfoContent(
              song: widget.song,
              player: widget.player,
              onOpenPlayer: widget.onOpenPlayer,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerSubtitleText extends StatelessWidget {
  final String text;
  final bool useProgressMarquee;
  final PlayerService player;
  final TextStyle style;

  const _MiniPlayerSubtitleText({
    required this.text,
    required this.useProgressMarquee,
    required this.player,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (!useProgressMarquee || text.trim().isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textAlign: TextAlign.left,
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(minWidth: 0);

        final overflow = painter.width - constraints.maxWidth;
        if (overflow <= 6) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        return ValueListenableBuilder<PlaybackSnapshot>(
          valueListenable: player.snapshot,
          builder: (context, snapshot, _) {
            final progress = _lineProgress(snapshot);
            final maxOffset = overflow + 24;
            return ClipRect(
              child: SizedBox(
                height: (style.fontSize ?? 12) * 1.35,
                child: Transform.translate(
                  offset: Offset(-maxOffset * progress, 0),
                  child: SizedBox(
                    width: painter.width,
                    child: Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: style,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double _lineProgress(PlaybackSnapshot snapshot) {
    final model = LyricsService.instance.controller.lyricNotifier.value;
    final index = LyricsService.instance.controller.activeIndexNotifiter.value;
    if (model == null || index < 0 || index >= model.lines.length) {
      final totalMs = snapshot.duration?.inMilliseconds ?? 0;
      if (totalMs <= 0) return 0;
      return (snapshot.position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    }

    final line = model.lines[index];
    final startMs = line.start.inMilliseconds;
    final nextStartMs = index + 1 < model.lines.length
        ? model.lines[index + 1].start.inMilliseconds
        : snapshot.duration?.inMilliseconds ??
              line.end?.inMilliseconds ??
              startMs;
    final endMs = (line.end?.inMilliseconds ?? nextStartMs).clamp(
      startMs + 1,
      1 << 30,
    );
    final currentMs = snapshot.position.inMilliseconds.clamp(startMs, endMs);
    return ((currentMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
  }
}

class MiniPlayerPlayButton extends StatelessWidget {
  final PlayerService player;
  final double size;
  final bool enabled;

  const MiniPlayerPlayButton({
    super.key,
    required this.player,
    required this.size,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PlaybackSnapshot>(
      valueListenable: player.snapshot,
      builder: (context, snapshot, child) {
        final totalMs = snapshot.duration?.inMilliseconds ?? 0;
        final progress = totalMs <= 0
            ? 0.0
            : snapshot.position.inMilliseconds / totalMs;
        final playing = snapshot.isPlaying;
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: enabled ? progress.clamp(0.0, 1.0) : 0.0,
                    strokeWidth: 1.8,
                    backgroundColor: scheme.outline.withValues(alpha: 0.12),
                    color: scheme.primary,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    playing ? AppIcons.pause : AppIcons.play,
                    color: scheme.onSurface,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: enabled ? player.togglePlayPause : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MiniPlayerQueueButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color color;

  const MiniPlayerQueueButton({
    super.key,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(AppIcons.queue, color: color, size: 24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onPressed,
      ),
    );
  }
}
