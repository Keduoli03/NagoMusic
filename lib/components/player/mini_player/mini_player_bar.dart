import 'package:flutter/material.dart';

import '../../../app/services/player_service.dart';
import '../../../app/router/app_router.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/state/song_state.dart';
import '../../common/artwork_widget.dart';
import '../../../pages/player/player_page.dart';
import '../../../pages/player/widgets/player_bottom_panel.dart';

class MiniPlayerBar extends StatelessWidget {
  static const double estimatedHeight = 72.0;

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
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.artworkSize = 48,
    this.borderRadius = 16,
    this.boxShadow,
    this.enableSwipe = true,
    this.trailing,
  }) : player = player ?? PlayerService.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackSnapshot>(
      valueListenable: player.snapshot,
      builder: (context, snapshot, child) {
        final song = snapshot.song;
        final hasSong = song != null;
        final scheme = Theme.of(context).colorScheme;
        final openPlayer = onOpenPlayer ??
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

        final bgColor = scheme.surface.withAlpha(242);
        final borderColor = scheme.outlineVariant.withAlpha(120);
        final material = Material(
          color: bgColor,
          elevation: boxShadow == null ? 8 : 0,
          shadowColor: Colors.black.withAlpha(38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            side: BorderSide(color: borderColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: openPlayer,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                children: [
                  MiniPlayerArtwork(
                    song: song,
                    size: artworkSize,
                    borderRadius: 4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MiniPlayerInfo(
                      song: song,
                      enableSwipe: enableSwipe,
                      player: player,
                      onOpenPlayer: openPlayer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  MiniPlayerPlayButton(
                    player: player,
                    size: 32,
                    enabled: hasSong,
                  ),
                  const SizedBox(width: 10),
                  trailing ??
                      MiniPlayerQueueButton(
                        onPressed: hasSong ? openQueue : null,
                        color: scheme.onSurface,
                      ),
                ],
              ),
            ),
          ),
        );

        return Padding(
          padding: padding,
          child: boxShadow == null
              ? material
              : Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: boxShadow,
                  ),
                  child: material,
                ),
        );
      },
    );
  }

  Route _playerRoute() {
    return PageRouteBuilder(
      settings: const RouteSettings(name: AppRoutes.player),
      pageBuilder: (context, animation, secondaryAnimation) => const PlayerPage(),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeOutCubic,
        );
        final offset =
            Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved);
        return SlideTransition(position: offset, child: child);
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
        child: Icon(
          Icons.music_note,
          color: scheme.onSurfaceVariant,
        ),
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
    if (!enableSwipe) {
      return _InfoContent(song: song, onOpenPlayer: onOpenPlayer);
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
  final VoidCallback onOpenPlayer;

  const _InfoContent({
    required this.song,
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
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 14,
          ),
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
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          song!.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
          ),
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
    _controller = AnimationController(
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
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: curve,
      ),
    );
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
              final value = _animation != null ? _animation!.value : _dragOffsetX;
              return Transform.translate(
                offset: Offset(value, 0),
                child: child,
              );
            },
            child: _InfoContent(
              song: widget.song,
              onOpenPlayer: widget.onOpenPlayer,
            ),
          ),
        ),
      ),
    );
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: enabled ? progress.clamp(0.0, 1.0) : 0.0,
                  strokeWidth: 2,
                  backgroundColor: scheme.outline.withAlpha(38),
                  color: scheme.primary,
                ),
              ),
              IconButton(
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: scheme.onSurface,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: enabled ? player.togglePlayPause : null,
              ),
            ],
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
      width: 40,
      height: 40,
      child: IconButton(
        icon: Icon(
          Icons.format_list_bulleted,
          color: color,
          size: 30,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onPressed,
      ),
    );
  }
}
