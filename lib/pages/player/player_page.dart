import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/haptic_service.dart';
import '../../app/services/lyrics/lyrics_service.dart';
import '../../app/services/playlists_service.dart';
import '../../app/services/player_service.dart';
import '../../app/state/settings_state.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/feedback/app_toast.dart';
import 'lyrics/lyric_view.dart';
import 'widgets/player_background.dart';
import 'widgets/player_bottom_panel.dart';
import 'widgets/player_immersive_layout.dart';
import 'widgets/player_header.dart';
import '../../app/utils/format_utils.dart';
import '../songs/show_song_detail_sheet.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  final PlayerService _player = PlayerService.instance;
  final PageController _pageController = PageController();
  late final AnimationController _dismissController;
  // Drives only the dismiss transform wrapper, so dragging doesn't rebuild the
  // whole player tree (background, header, lyrics, controls) every frame.
  final ValueNotifier<double> _dismissOffset = ValueNotifier(0);
  double? _dismissDragStartY;

  @override
  void initState() {
    super.initState();
    _dismissController =
        AnimationController.unbounded(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (!mounted) return;
          _dismissOffset.value = _dismissController.value;
        });
  }

  void _handleDismissDragStart(DragStartDetails details) {
    _dismissController.stop();
    _dismissDragStartY = details.globalPosition.dy;
  }

  void _handleDismissDragUpdate(DragUpdateDetails details) {
    final startY = _dismissDragStartY;
    if (startY == null) return;
    final offset = details.globalPosition.dy - startY;
    if (offset <= 0) return;
    final maxOffset = MediaQuery.sizeOf(context).height;
    final clamped = offset.clamp(0.0, maxOffset);
    _dismissOffset.value = clamped;
    _dismissController.value = clamped;
  }

  void _handleDismissDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss = _dismissOffset.value > 72 || velocity > 700;
    final startOffset = _dismissOffset.value;
    _dismissDragStartY = null;
    if (shouldDismiss) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      final remaining = (screenHeight - startOffset).clamp(120.0, screenHeight);
      _dismissController.duration = Duration(
        milliseconds: velocity > 0
            ? (remaining / velocity * 1000).clamp(120, 240).round()
            : 180,
      );
      _dismissController.value = startOffset;
      _dismissController
          .animateTo(screenHeight, curve: Curves.easeOutCubic)
          .whenComplete(() {
            if (!mounted) return;
            _closePlayer();
          });
      return;
    }
    _dismissController.duration = const Duration(milliseconds: 220);
    _dismissController.value = startOffset;
    _dismissController.animateBack(0, curve: Curves.easeOutCubic);
  }

  void _handleDismissDragCancel() {
    if (_dismissOffset.value == 0) return;
    _dismissDragStartY = null;
    _dismissController.duration = const Duration(milliseconds: 220);
    _dismissController.value = _dismissOffset.value;
    _dismissController.animateBack(0, curve: Curves.easeOutCubic);
  }

  void _closePlayer() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  @override
  void dispose() {
    _dismissController.dispose();
    _pageController.dispose();
    _dismissOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Let system back / predictive-back pop the player route normally. Using
    // canPop:false here made HarmonyOS predictive-back render "exit to home"
    // and sometimes commit it, jumping to the desktop instead of closing the
    // player. The drag-to-dismiss path calls _closePlayer() directly.
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          // 长按空白处打开这首歌的「更多」面板，不用绕去底部操作栏或设置页。
          // behavior 用 translucent 而不是 opaque：它只是在竞技场里多加一个
          // 候选人，快速点击（按钮、拖拽关闭）该怎么响应还怎么响应——长按
          // 识别器在指针提前抬起或发生位移时会自己认输，不会拖慢或吞掉下面
          // 控件的点击。
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (_) => _openMorePanel(context),
          child: ValueListenableBuilder<double>(
            valueListenable: _dismissOffset,
            builder: (context, dragOffset, child) {
              final dismissProgress = (dragOffset / 120).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, dragOffset),
                child: Opacity(
                  opacity: 1 - dismissProgress * 0.08,
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(dismissProgress * 24),
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: Stack(
              children: [
                RepaintBoundary(
                  child: PlayerBackground(
                    songSignal: _player.currentSongSignal,
                  ),
                ),
                PlayerTheme(
                  child: ValueListenableBuilder<PlayerStylePreset>(
                    valueListenable: PlayerStyleSettings.stylePreset,
                    builder: (context, stylePreset, _) {
                      // 海报和沉浸都是通栏样式：不画公共头部，也不套 SafeArea，
                      // 这样封面 / 背景能顶到屏幕边缘。代价是歌词页要自己把
                      // 状态栏和导航栏的安全区补回来，见下面那个 Padding。
                      final isFullBleed =
                          stylePreset == PlayerStylePreset.poster ||
                          stylePreset == PlayerStylePreset.immersive;
                      final topInset = MediaQuery.paddingOf(context).top;
                      final bottomInset = MediaQuery.paddingOf(context).bottom;
                      return SafeArea(
                        top: !isFullBleed,
                        bottom: !isFullBleed,
                        child: Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragStart: _handleDismissDragStart,
                              onVerticalDragUpdate: _handleDismissDragUpdate,
                              onVerticalDragEnd: _handleDismissDragEnd,
                              onVerticalDragCancel: _handleDismissDragCancel,
                              child: isFullBleed
                                  ? const SizedBox.shrink()
                                  : PlayerHeader(
                                      songSignal: _player.currentSongSignal,
                                      stylePreset: stylePreset,
                                    ),
                            ),
                            Expanded(
                              child: PageView(
                                controller: _pageController,
                                children: [
                                  _PlayerView(
                                    player: _player,
                                    onTapLyrics: () =>
                                        _pageController.animateToPage(
                                          1,
                                          duration: const Duration(
                                            milliseconds: 280,
                                          ),
                                          curve: Curves.easeOut,
                                        ),
                                  ),
                                  isFullBleed
                                      ? Padding(
                                          padding: EdgeInsets.only(
                                            top: topInset,
                                            bottom: bottomInset,
                                          ),
                                          child: const PlayerLyricsView(),
                                        )
                                      : const PlayerLyricsView(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 长按空白处打开「更多」——歌曲详情/操作面板，和底部操作栏「更多」按钮
  /// 打开的是同一个面板（[showSongDetailSheet]），包括收藏、加入歌单、下载、
  /// 歌曲信息，以及跳去「播放器外观」的入口。
  ///
  /// 一开始做成了单独弹一个"播放样式"网格，后来发现这不是用户要的——长按
  /// 应该是这首歌的快捷菜单，样式切换只是其中顺带能到达的一站，不该是
  /// 长按唯一能做的事。
  void _openMorePanel(BuildContext context) {
    final song = _player.currentSong.value;
    if (song == null) {
      AppToast.show(context, '暂无歌曲');
      return;
    }
    Haptics.impact();
    showSongDetailSheet(context, song: song, enablePlayerAppearanceEntry: true);
  }
}

class _PlayerView extends StatelessWidget {
  final PlayerService player;
  final VoidCallback onTapLyrics;

  const _PlayerView({required this.player, required this.onTapLyrics});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerStylePreset>(
      valueListenable: PlayerStyleSettings.stylePreset,
      builder: (context, stylePreset, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppLayoutSettings.tabletMode,
          builder: (context, tabletMode, _) {
            final mq = MediaQuery.of(context);
            final isTabletLandscape =
                tabletMode &&
                mq.orientation == Orientation.landscape &&
                mq.size.width >= 900;
            if (!isTabletLandscape) {
              if (stylePreset == PlayerStylePreset.poster) {
                return _PosterPlayerLayout(player: player);
              }
              if (stylePreset == PlayerStylePreset.immersive) {
                return PlayerImmersiveLayout(player: player);
              }
              return _MobilePlayerLayout(
                player: player,
                stylePreset: stylePreset,
                onTapLyrics: onTapLyrics,
              );
            }
            return _TabletLandscapePlayerLayout(
              player: player,
              stylePreset: stylePreset,
              onTapLyrics: onTapLyrics,
            );
          },
        );
      },
    );
  }
}

class _MobilePlayerLayout extends StatelessWidget {
  final PlayerService player;
  final PlayerStylePreset stylePreset;
  final VoidCallback onTapLyrics;

  const _MobilePlayerLayout({
    required this.player,
    required this.stylePreset,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _PlayerLayoutSpec.fromPreset(stylePreset);
    return Column(
      children: [
        Spacer(flex: spec.topSpacerFlex),
        _PlayerArtwork(
          songSignal: player.currentSongSignal,
          stylePreset: stylePreset,
        ),
        if (spec.middleSpacerFlex > 0) Spacer(flex: spec.middleSpacerFlex),
        PlayerBottomPanel(
          player: player,
          stylePreset: stylePreset,
          onTapLyrics: onTapLyrics,
        ),
      ],
    );
  }
}

class _TabletLandscapePlayerLayout extends StatelessWidget {
  final PlayerService player;
  final PlayerStylePreset stylePreset;
  final VoidCallback onTapLyrics;

  const _TabletLandscapePlayerLayout({
    required this.player,
    required this.stylePreset,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    const lyricRadius = 24.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                const Spacer(),
                Expanded(
                  flex: 8,
                  child: Center(
                    child: _PlayerArtwork(
                      songSignal: player.currentSongSignal,
                      stylePreset: stylePreset,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                PlayerHeader(
                  songSignal: player.currentSongSignal,
                  stylePreset: stylePreset,
                ),
                const SizedBox(height: 8),
                // Playback controls were missing entirely in tablet landscape.
                // Reuse the panel (without its mini-lyrics, since full lyrics
                // already show on the right).
                PlayerBottomPanel(
                  player: player,
                  stylePreset: stylePreset,
                  onTapLyrics: onTapLyrics,
                  showMiniLyrics: false,
                ),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(lyricRadius),
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.16),
                child: const PlayerLyricsView(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerLayoutSpec {
  final int topSpacerFlex;
  final int middleSpacerFlex;

  const _PlayerLayoutSpec({
    required this.topSpacerFlex,
    required this.middleSpacerFlex,
  });

  factory _PlayerLayoutSpec.fromPreset(PlayerStylePreset preset) {
    switch (preset) {
      // 沉浸样式在手机上走 PlayerImmersiveLayout，用不到这个 spec；
      // 平板横屏仍会落到通用布局，所以照 poster 给一份。
      case PlayerStylePreset.immersive:
      case PlayerStylePreset.poster:
        return const _PlayerLayoutSpec(topSpacerFlex: 1, middleSpacerFlex: 1);
      case PlayerStylePreset.classic:
        return const _PlayerLayoutSpec(topSpacerFlex: 1, middleSpacerFlex: 1);
    }
  }
}

class _PosterPlayerLayout extends StatelessWidget {
  final PlayerService player;

  const _PosterPlayerLayout({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Watch.builder(
      builder: (context) {
        final song = player.currentSongSignal.value;
        final title = song?.title.trim().isNotEmpty == true
            ? song!.title.trim()
            : '未知歌曲';
        final artist = song?.artist.trim().isNotEmpty == true
            ? song!.artist.trim()
            : '未知艺术家';
        return Column(
          children: [
            _PosterArtwork(songSignal: player.currentSongSignal),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  24,
                  mq.size.height < 760 ? 12 : 18,
                  24,
                  bottomInset > 20 ? bottomInset + 8 : 18,
                ),
                // Transparent so the cover-color + 流光 background shows through,
                // matching the lyrics page (no solid white panel).
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 3),
                    Skeletonizer(
                      enabled: song == null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.86),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _PosterLyricsPreview(),
                        ],
                      ),
                    ),
                    const Spacer(flex: 2),
                    _PosterMetaRow(player: player, song: song),
                    const SizedBox(height: 2),
                    _PosterSeekBar(player: player),
                    const SizedBox(height: 8),
                    _PosterControls(player: player),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PosterArtwork extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const _PosterArtwork({required this.songSignal});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenHeight * 0.46).clamp(270.0, 430.0);
    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
        return SizedBox(
          height: heroHeight,
          width: double.infinity,
          // Fade the cover's bottom to transparent so it dissolves into the
          // cover-color + 流光 background below (instead of a hard edge / white).
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.72, 1.0],
            ).createShader(rect),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final boxSize = constraints.maxWidth > constraints.maxHeight
                        ? constraints.maxWidth
                        : constraints.maxHeight;
                    final child = song == null
                        ? Skeletonizer(
                            enabled: true,
                            child: _ArtworkPlaceholder(
                              border: BorderRadius.zero,
                              label: '',
                            ),
                          )
                        : ArtworkWidget(
                            song: song,
                            size: boxSize,
                            borderRadius: 0,
                            preferOriginal: true,
                            keepPreviousUntilLoaded: true,
                            placeholder: Skeletonizer(
                              enabled: true,
                              child: _ArtworkPlaceholder(
                                border: BorderRadius.zero,
                                label: song.title,
                              ),
                            ),
                          );
                    return ClipRect(
                      child: OverflowBox(
                        maxWidth: boxSize,
                        maxHeight: boxSize,
                        child: child,
                      ),
                    );
                  },
                ),
                // Subtle top scrim so status-bar icons stay legible over art.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x1A000000), Colors.transparent],
                      stops: [0.0, 0.22],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PosterLyricsPreview extends StatelessWidget {
  const _PosterLyricsPreview();

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final lyrics = LyricsService.instance;
        final snap = lyrics.snapshotSignal.value;
        final model = lyrics.lyricModelSignal.value;
        final lines = model?.lines ?? const <LyricLine>[];
        final active = lyrics.activeIndexSignal.value;
        // No skeleton: keep blank while loading a new song's lyrics, show the
        // real lines as soon as they arrive.
        if (snap.status == LyricsLoadStatus.loading && lines.isEmpty) {
          return const SizedBox.shrink();
        }
        if (lines.isEmpty) {
          // Don't echo the song title/artist here — they already show in the
          // header above; use neutral placeholders to avoid duplication.
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PosterLyricLine(text: '暂无歌词', active: true),
              SizedBox(height: 8),
              _PosterLyricLine(text: '纯音乐或未匹配到歌词', active: false),
              SizedBox(height: 8),
              _PosterLyricLine(text: ' ', active: false),
            ],
          );
        }

        final base = (active >= 0 && active < lines.length) ? active : 0;
        String lineAt(int index) {
          if (index < 0 || index >= lines.length) return ' ';
          return lines[index].text.trim().isEmpty ? ' ' : lines[index].text;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PosterLyricLine(text: lineAt(base - 1), active: false),
            const SizedBox(height: 8),
            _PosterLyricLine(text: lineAt(base), active: true),
            const SizedBox(height: 8),
            _PosterLyricLine(text: lineAt(base + 1), active: false),
          ],
        );
      },
    );
  }
}

class _PosterLyricLine extends StatelessWidget {
  final String text;
  final bool active;

  const _PosterLyricLine({required this.text, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: active
            ? scheme.onSurface.withValues(alpha: 0.92)
            : scheme.onSurfaceVariant.withValues(alpha: 0.68),
        fontSize: active ? 18 : 15,
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        height: 1.15,
      ),
    );
  }
}

class _PosterMetaRow extends StatelessWidget {
  final PlayerService player;
  final SongEntity? song;

  const _PosterMetaRow({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _PosterFavoriteButton(song: song),
        const Spacer(),
        IconButton(
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          icon: Icon(
            AppIcons.menu,
            color: scheme.onSurface.withValues(alpha: 0.72),
            size: 24,
          ),
          onPressed: () => showPlayerPlaylistSheet(context, player),
        ),
      ],
    );
  }
}

class _PosterFavoriteButton extends StatefulWidget {
  final SongEntity? song;

  const _PosterFavoriteButton({required this.song});

  @override
  State<_PosterFavoriteButton> createState() => _PosterFavoriteButtonState();
}

class _PosterFavoriteButtonState extends State<_PosterFavoriteButton> {
  final PlaylistsService _playlists = PlaylistsService.instance;
  bool _isFavorite = false;
  bool _loading = false;
  String _favoriteName = PlaylistsService.favoritePlaylistName;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
  }

  @override
  void didUpdateWidget(covariant _PosterFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song?.id != widget.song?.id) {
      _loadFavoriteState();
    }
  }

  Future<void> _loadFavoriteState() async {
    final song = widget.song;
    if (song == null) {
      if (mounted) {
        setState(() {
          _isFavorite = false;
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    final list = await _playlists.loadAll();
    PlaylistEntity? favorite;
    for (final p in list) {
      if (p.isFavorite || p.id == PlaylistsService.favoritePlaylistId) {
        favorite = p;
        break;
      }
    }
    if (!mounted || widget.song?.id != song.id) return;
    final name = (favorite?.name ?? '').trim();
    setState(() {
      _isFavorite = favorite?.songIds.contains(song.id) ?? false;
      _loading = false;
      if (name.isNotEmpty) {
        _favoriteName = name;
      }
    });
  }

  Future<void> _toggleFavorite() async {
    final song = widget.song;
    if (_loading || song == null) return;
    setState(() => _loading = true);
    if (_isFavorite) {
      await _playlists.removeSongs(PlaylistsService.favoritePlaylistId, [
        song.id,
      ]);
      if (!mounted) return;
      setState(() {
        _isFavorite = false;
        _loading = false;
      });
      AppToast.show(context, '已从$_favoriteName移出');
    } else {
      await _playlists.addSongs(PlaylistsService.favoritePlaylistId, [song.id]);
      if (!mounted) return;
      setState(() {
        _isFavorite = true;
        _loading = false;
      });
      AppToast.show(context, '已添加到$_favoriteName');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(
        _isFavorite ? AppIconsFilled.heart : AppIcons.heart,
        color: _isFavorite
            ? Colors.deepOrangeAccent
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
        size: 24,
      ),
      onPressed: widget.song == null || _loading ? null : _toggleFavorite,
    );
  }
}

class _PosterSeekBar extends StatefulWidget {
  final PlayerService player;

  const _PosterSeekBar({required this.player});

  @override
  State<_PosterSeekBar> createState() => _PosterSeekBarState();
}

class _PosterSeekBarState extends State<_PosterSeekBar> with SignalsMixin {
  late final _dragValue = createSignal<double?>(null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final position = widget.player.positionSignal.value;
        final duration = widget.player.durationSignal.value;
        final totalMs = duration?.inMilliseconds ?? 0;
        final max = totalMs <= 0 ? 1.0 : totalMs.toDouble();
        final currentMs = position.inMilliseconds.clamp(0, max.toInt()).toInt();
        final value = (_dragValue.value ?? currentMs.toDouble()).clamp(0, max);
        return Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    formatClock(Duration(milliseconds: currentMs)),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: scheme.onSurface.withValues(
                        alpha: 0.64,
                      ),
                      inactiveTrackColor: scheme.onSurface.withValues(
                        alpha: 0.14,
                      ),
                      thumbColor: scheme.onSurface,
                    ),
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: max,
                      onChanged: totalMs <= 0
                          ? null
                          : (next) => _dragValue.value = next,
                      onChangeEnd: totalMs <= 0
                          ? null
                          : (next) {
                              _dragValue.value = null;
                              widget.player.seek(
                                Duration(milliseconds: next.round()),
                              );
                            },
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    formatClock(duration),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.only(top: 2),
              color: scheme.onSurface.withValues(alpha: 0.04),
            ),
          ],
        );
      },
    );
  }
}

class _PosterControls extends StatelessWidget {
  final PlayerService player;

  const _PosterControls({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurface;
    return Watch.builder(
      builder: (context) {
        final playing = player.isPlayingSignal.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: 30,
              color: iconColor,
              icon: const Icon(AppIcons.repeat),
              onPressed: player.cyclePlaybackMode,
            ),
            IconButton(
              iconSize: 40,
              color: iconColor,
              icon: const Icon(AppIconsFilled.skipPrevious),
              onPressed: player.previous,
            ),
            IconButton(
              iconSize: 44,
              color: iconColor,
              icon: Icon(playing ? AppIconsFilled.pause : AppIconsFilled.play),
              onPressed: player.togglePlayPause,
            ),
            IconButton(
              iconSize: 40,
              color: iconColor,
              icon: const Icon(AppIconsFilled.skipNext),
              onPressed: player.next,
            ),
            IconButton(
              iconSize: 30,
              color: iconColor,
              icon: const Icon(AppIcons.moreVertical),
              onPressed: () => _showPosterSongDetailSheet(context, player),
            ),
          ],
        );
      },
    );
  }
}

void _showPosterSongDetailSheet(BuildContext context, PlayerService player) {
  final song = player.currentSong.value;
  if (song == null) {
    AppToast.show(context, '暂无歌曲');
    return;
  }
  showSongDetailSheet(context, song: song, enablePlayerAppearanceEntry: true);
}

class _PlayerArtwork extends StatelessWidget {
  final Signal<SongEntity?> songSignal;
  final PlayerStylePreset stylePreset;

  const _PlayerArtwork({required this.songSignal, required this.stylePreset});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLayoutSettings.tabletMode,
      builder: (context, tabletMode, _) {
        final isTabletLayout =
            tabletMode && MediaQuery.sizeOf(context).width >= 720;
        return Watch.builder(
          builder: (context) {
            final song = songSignal.value;
            final spec = _ArtworkSpec.fromPreset(stylePreset, isTabletLayout);
            final border = BorderRadius.circular(spec.borderRadius);
            final maxSize = spec.maxSize;
            if (song == null) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: spec.horizontalInset),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxWidth;
                    final boxSize = size < maxSize ? size : maxSize;
                    return Center(
                      child: SizedBox(
                        width: boxSize,
                        height: boxSize,
                        child: _ArtworkShadowContainer(
                          border: border,
                          child: _ArtworkPlaceholder(border: border, label: ''),
                        ),
                      ),
                    );
                  },
                ),
              );
            }
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: spec.horizontalInset),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth;
                  final boxSize = size < maxSize ? size : maxSize;
                  return Center(
                    child: SizedBox(
                      width: boxSize,
                      height: boxSize,
                      child: _ArtworkShadowContainer(
                        border: border,
                        child: ArtworkWidget(
                          song: song,
                          size: boxSize,
                          borderRadius: 12,
                          preferOriginal: true,
                          keepPreviousUntilLoaded: true,
                          placeholder: _ArtworkPlaceholder(
                            border: border,
                            label: song.title,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtworkSpec {
  final double borderRadius;
  final double horizontalInset;
  final double maxSize;

  const _ArtworkSpec({
    required this.borderRadius,
    required this.horizontalInset,
    required this.maxSize,
  });

  factory _ArtworkSpec.fromPreset(PlayerStylePreset preset, bool isTablet) {
    switch (preset) {
      case PlayerStylePreset.immersive:
      case PlayerStylePreset.poster:
        return _ArtworkSpec(
          borderRadius: 0,
          horizontalInset: 0,
          maxSize: isTablet ? 360 : double.infinity,
        );
      case PlayerStylePreset.classic:
        return _ArtworkSpec(
          borderRadius: 12,
          horizontalInset: 32,
          maxSize: isTablet ? 320 : double.infinity,
        );
    }
  }
}

class _ArtworkShadowContainer extends StatelessWidget {
  final BorderRadius border;
  final Widget child;

  const _ArtworkShadowContainer({required this.border, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: border, child: child);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  final BorderRadius border;
  final String label;

  const _ArtworkPlaceholder({required this.border, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = label.trim().isEmpty ? '?' : label.trim().substring(0, 1);
    return Container(
      decoration: BoxDecoration(
        borderRadius: border,
        color: scheme.primary.withValues(alpha: 0.12),
      ),
      child: Center(
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
