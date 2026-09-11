import 'dart:ui';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/router/app_router.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/theme/app_glass.dart';
import '../../../app/state/song_state.dart';
import '../../common/artwork_widget.dart';
import '../../layout/bottom_chrome.dart';
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

  /// 作为底栏的 `bottomAccessory` 挂在 `GlassTabBar.minimizable` 上。
  ///
  /// 这种模式下位置、宽度、高度全由底栏那套布局算（它要让播放器在收起时滑到
  /// Tab 圆圈旁边去），所以这里不能再自己套 [padding]，也不能让高度跟着内容走 ——
  /// 一律 [BottomChrome.accessoryHeight]。
  final bool asAccessory;

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
    this.asAccessory = false,
  }) : player = player ?? PlayerService.instance;

  @override
  Widget build(BuildContext context) {
    // 底栏收起时，播放器要跟着缩成一条窄条塞进那一行 —— 这时候宽度只剩
    // 「Tab 圆圈和搜索圆圈之间」那一段，两行字 + 队列按钮塞不下，得换个排法。
    // 这个状态由底栏通过 InheritedWidget 播下来；不在底栏里（详情页单独浮着的
    // 那种）读不到 scope，默认就是 expanded。
    final compact =
        asAccessory &&
        GlassTabBarAccessoryPlacementScope.of(context) ==
            GlassTabBarAccessoryPlacement.inline;

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
              Navigator.of(context).push(_playerRoute());
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

        // 挂在底栏上时高度是定死的，封面就按它来算，不用外面传的 artworkSize——
        // 上下各留 6 的呼吸，剩下的全给封面，正方形。
        final art = asAccessory
            ? BottomChrome.accessoryHeight - 12
            : artworkSize;

        // 行内容三种形态共用同一套零件，只是收起时把「副标题」和「队列按钮」
        // 摘掉 —— 那一段宽度只够放下封面、歌名和一个播放键。
        final rowContent = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 10,
            vertical: asAccessory ? 6 : 7,
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
                  size: art,
                  borderRadius: 10,
                ),
              ),
              SizedBox(width: compact ? 8 : 11),
              Expanded(
                child: compact
                    ? Text(
                        song?.title ?? '未在播放',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hasSong
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      )
                    : MiniPlayerInfo(
                        song: song,
                        enableSwipe: enableSwipe,
                        player: player,
                        onOpenPlayer: openPlayer,
                      ),
              ),
              SizedBox(width: compact ? 4 : 6),
              MiniPlayerPlayButton(
                player: player,
                size: compact ? 32 : 38,
                enabled: hasSong,
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                trailing ??
                    MiniPlayerQueueButton(
                      onPressed: hasSong ? openQueue : null,
                      color: scheme.onSurface,
                    ),
              ],
              const SizedBox(width: 2),
            ],
          ),
        );

        // 进度条不在这条上。
        //
        // 原来是画在播放键外面的一圈环：环只有走过的那一段有颜色，落在磨砂玻璃上
        // 就是一道孤零零的弧线，读不出是「进度」，还把整条播放器唯一的主操作挤得
        // 很花。想挪成胶囊底边一条细线也不行 —— 胶囊只有 52 高，封面正好占满内高，
        // 细线必然压在封面和按钮上。
        //
        // 所以干脆不放，和 Apple Music 的迷你播放器一致：这一条的职责是「现在在放
        // 什么 + 停 / 继续」，要看进度、要拖，点开全屏播放器，那里有完整的进度条。
        final row = rowContent;

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
              child: row,
            ),
          ),
        );

        Widget styled = ValueListenableBuilder<AppBottomBarStyle>(
          valueListenable: AppLayoutSettings.bottomBarStyle,
          builder: (context, barStyle, _) {
            // 材质**只**跟着底栏样式走，判断条件必须和 ModernNavigationBar 里
            // 那一行一模一样。
            //
            // 这里原本还并了一个 AppBackgroundSettings.glassEffectEnabled ——
            // 那是「毛玻璃质感」功能删掉后留下的遗留 notifier，被钉死在 false
            // 且没有任何 UI 能打开。并上它的结果是这个分支永远进不去：底栏是
            // 玻璃、播放器是白卡片，上下贴着两种材质。多判一个开关就多一个
            // 它俩会不一致的理由。
            if (barStyle == AppBottomBarStyle.liquidGlass) {
              // 圆角和玻璃参数都从 AppGlass 取，和底栏是同一份。
              // 收起后它跟 Tab 圆圈并排，圆角要跟着那个圆圈走，否则一个圆
              // 一个方角，并排看着就是两件东西。
              final r = compact
                  ? BottomChrome.accessoryHeight / 2
                  : AppGlass.radius;
              return GlassContainer(
                shape: LiquidRoundedSuperellipse(borderRadius: r),
                settings: AppGlass.panel(context),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(r),
                    onTap: openPlayer,
                    child: row,
                  ),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: boxShadow ?? defaultShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: ValueListenableBuilder<double>(
                  valueListenable: AppBackgroundSettings.panelBlurStrength,
                  builder: (context, blurStrength, _) {
                    if (blurStrength <= 0) return content;
                    return BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurStrength,
                        sigmaY: blurStrength,
                      ),
                      child: content,
                    );
                  },
                ),
              ),
            );
          },
        );

        // 挂在底栏上时外面那层 Padding 由底栏的 horizontalPadding 负责，
        // 这里再加一层就会比底栏窄一圈、左右对不齐。
        if (asAccessory) return styled;
        return Padding(padding: padding, child: styled);
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
        final playing = snapshot.isPlaying;
        return _MiniPlayerCircleButton(
          size: size,
          // 实心三角 / 双竖条。空心描边的图标读起来像装饰，实心才像「一个按钮」，
          // 而且这颗是整条播放器上唯一的主操作，该比旁边的队列键重。
          icon: playing ? AppIconsFilled.pause : AppIconsFilled.play,
          iconSize: size * 0.44,
          foreground: scheme.primary,
          background: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.14),
            scheme.surface,
          ),
          onPressed: enabled ? player.togglePlayPause : null,
          semanticLabel: playing ? '暂停' : '播放',
        );
      },
    );
  }
}

class MiniPlayerQueueButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color color;

  /// 直径。默认和播放键同一档 —— 它俩是并排的一对，差一点就看着没对齐。
  final double size;

  const MiniPlayerQueueButton({
    super.key,
    required this.onPressed,
    required this.color,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 和播放键同一个模子，只有分量不同：底色用中性的 onSurface 而不是主题色，
    // 图标也保持描边。两颗一样大、一样圆，一眼看过去是一对；主次靠颜色和实心
    // 与否来分，而不是靠一颗有壳、一颗是光秃秃一个字形 —— 之前就是后者，队列键
    // 像是飘在旁边没放进控件里。
    return _MiniPlayerCircleButton(
      size: size,
      icon: AppIcons.queue,
      iconSize: size * 0.5,
      foreground: onPressed == null ? color.withValues(alpha: 0.38) : color,
      background: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.07),
        scheme.surface,
      ),
      onPressed: onPressed,
      semanticLabel: '播放列表',
    );
  }
}

/// 迷你播放器上那一对圆钮的共同外形。
///
/// 单独抽出来是因为「长得一样」本身就是设计意图：两颗按钮任何一处尺寸、圆度、
/// 底色算法写成两份，改一处忘另一处，它俩就会慢慢错开。
class _MiniPlayerCircleButton extends StatelessWidget {
  const _MiniPlayerCircleButton({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.foreground,
    required this.background,
    required this.onPressed,
    required this.semanticLabel,
  });

  final double size;
  final IconData icon;
  final double iconSize;
  final Color foreground;
  final Color background;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          // 底色必须是 alphaBlend 出来的**不透明**色。这一对压在磨砂玻璃上，
          // 玻璃把背后糊成一片浅灰，直接给半透明色会被吃得几乎看不见。
          color: disabled ? Colors.transparent : background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: disabled
                    ? foreground.withValues(alpha: 0.38)
                    : foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
