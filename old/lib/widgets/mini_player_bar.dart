import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../core/router/navigator_util.dart';
import '../pages/player_page.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/marquee_text.dart';

class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
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

  String _truncateTitle(String title) {
    final index = title.indexOf(')');
    if (index != -1) {
      return title.substring(0, index + 1);
    }
    return title;
  }

  void _openPlayerPage() {
    NavigatorUtil.navigatorKey.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/player'),
        fullscreenDialog: true,
        builder: (_) => const PlayerPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.playbackTick);
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.lyricsTick);
      final pos = vm.position;
      final dur = vm.duration;
      final progress = dur.inMilliseconds == 0
          ? 0.0
          : pos.inMilliseconds / dur.inMilliseconds;
      final hasSong = vm.currentSong != null;

      final colorScheme = Theme.of(context).colorScheme;
      final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

      Widget artworkWidget;
      if (vm.currentSong != null) {
        artworkWidget = ArtworkWidget(
          song: vm.currentSong!,
          size: 48,
          borderRadius: 4,
        );
      } else {
        artworkWidget = Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Icon(
              Icons.music_note,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openPlayerPage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                      children: [
                        artworkWidget,
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRect(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _openPlayerPage,
                              onHorizontalDragUpdate: (details) {
                                if (!hasSong) return;
                                setState(() {
                                  final delta = details.primaryDelta ?? 0;
                                  _dragOffsetX =
                                      (_dragOffsetX + delta).clamp(-80.0, 80.0);
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
                                    vm.next();
                                  } else {
                                    vm.previous();
                                  }
                                }
                                _animateBack();
                              },
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: AnimatedBuilder(
                                  animation: _controller,
                                  builder: (context, child) {
                                    final value =
                                        _animation != null ? _animation!.value : _dragOffsetX;
                                    return Transform.translate(
                                      offset: Offset(value, 0),
                                      child: child,
                                    );
                                  },
                                  child: hasSong
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            MarqueeText(
                                              _truncateTitle(vm.title ?? ''),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Builder(
                                              builder: (context) {
                                                final lines = vm.lyricsLines;
                                                final idx = vm.currentLyricIndex;
                                                String subtitle;
                                                if (lines.isNotEmpty &&
                                                    idx >= 0 &&
                                                    idx < lines.length &&
                                                    lines[idx].text
                                                        .trim()
                                                        .isNotEmpty) {
                                                  subtitle = lines[idx].text;
                                                } else {
                                                  subtitle = vm.artist ?? '';
                                                }
                                                return Text(
                                                  subtitle,
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                );
                                              },
                                            ),
                                          ],
                                        )
                                      : Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '未选择歌曲',
                                            style: TextStyle(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  value: hasSong ? progress.clamp(0.0, 1.0) : 0.0,
                                  strokeWidth: 2,
                                  backgroundColor:
                                      colorScheme.outline.withValues(alpha: 0.15),
                                  color: colorScheme.primary,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  vm.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: colorScheme.onSurface,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: hasSong
                                    ? () {
                                        vm.isPlaying ? vm.pause() : vm.play();
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            icon: Icon(
                              Icons.format_list_bulleted,
                              color: colorScheme.onSurface,
                              size: 32,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              final ctx = NavigatorUtil.context;
                              if (ctx == null) return;
                              showModalBottomSheet(
                                context: ctx,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                builder: (_) => const PlaylistSheet(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    },);
  }
}
