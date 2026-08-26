import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:signals/signals_flutter.dart';

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/state/song_state.dart';
import '../../../app/theme/tokens.dart';
import 'particle_cover.dart';
import 'player_bottom_panel.dart';

/// 「沉浸」播放样式。
///
/// 三个和另外两版不一样的地方，也是这一版的全部性格所在：
///
/// 1. **标题在封面上面**，不是下面。一进页面先读到歌名，封面是插图不是主角。
/// 2. **封面边缘是粒子材质**（见 [ParticleCover]）：主体保持高清原图，只有
///    最外一圈逐渐碎片化；切歌时旧封面飞散、新封面再聚拢回来。
/// 3. **不自己画背景**，沿用默认样式那套封面取色流光（`PlayerBackground` 挂在
///    `player_page.dart` 的 Stack 底层），但这一样式始终要求深色亮度，不随应用
///    的浅色模式变成浅背景。
///
/// 下方保留进度条与时间，可直接拖动定位。
class PlayerImmersiveLayout extends StatelessWidget {
  const PlayerImmersiveLayout({super.key, required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Watch.builder(
      builder: (context) {
        final song = player.currentSongSignal.value;
        // 不自己画背景：沿用默认样式那套封面取色流光（PlayerBackground 在
        // player_page 的 Stack 底层），这一层保持透明。
        return Padding(
          padding: EdgeInsets.only(
            top: topInset + AppSpacing.xl,
            bottom: bottomInset + AppSpacing.md,
          ),
          child: Column(
            children: [
              _TitleBlock(song: song),
              const Spacer(flex: 2),
              _CoverStage(song: song, player: player),
              const Spacer(flex: 3),
              const _ImmersiveLyrics(),
              const Spacer(flex: 2),
              PlayerSeekBar(
                player: player,
                stylePreset: PlayerStylePreset.immersive,
              ),
              AppSpacing.gapXs,
              _ImmersiveControls(player: player),
              AppSpacing.gapSm,
              _QueueIndicator(player: player),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 标题

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.song});

  final SongEntity? song;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (song?.title ?? '').trim();
    final artist = (song?.artist ?? '').trim();
    // 衬线体是这一版的识别点：另外两版都是无衬线，换成衬线之后哪怕只看一眼
    // 顶部也能认出是哪个样式。用系统 serif，不额外打包字体。
    return Padding(
      padding: AppSpacing.page,
      child: Column(
        children: [
          Text(
            title.isEmpty ? '未知歌曲' : title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.display
                .on(scheme.onSurface)
                .copyWith(fontFamily: 'serif', letterSpacing: 1.5),
          ),
          AppSpacing.gapXs,
          Text(
            artist.isEmpty ? '未知艺术家' : artist,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.section
                .on(scheme.onSurface.withValues(alpha: 0.82))
                .copyWith(fontFamily: 'serif', letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 封面

/// 封面方框的边长（逻辑像素）。传给 [ParticleCover] 用来换算解码分辨率，
/// 必须和这里的显示尺寸一致——两边算错任何一处，都会回到"解码的比显示的
/// 小"那个糊的老问题。
double _coverSide(double screenWidth) =>
    (screenWidth * 0.72).clamp(200.0, 380.0);

class _CoverStage extends StatelessWidget {
  const _CoverStage({required this.song, required this.player});

  final SongEntity? song;
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final side = _coverSide(MediaQuery.sizeOf(context).width);
    return SizedBox(
      width: side,
      height: side,
      child: Watch.builder(
        builder: (context) {
          final positionMs = player.positionSignal.value.inMilliseconds;
          final reportedDurationMs =
              player.durationSignal.value?.inMilliseconds ?? 0;
          final durationMs = reportedDurationMs > 0
              ? reportedDurationMs
              : song?.durationMs ?? 0;
          final progress = durationMs > 0
              ? (positionMs / durationMs).clamp(0.0, 1.0)
              : 0.0;
          return ParticleCover(
            song: song,
            side: side,
            playbackProgress: progress,
            isPlaying: player.isPlayingSignal.value,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- 双语歌词

/// 居中双语歌词，当前行加粗高亮，前后各一行淡出。
///
/// 只取三行：这一版封面占了中间一大块，歌词区被压得比「海报歌词」窄，
/// 再多行会顶到控制条上。
class _ImmersiveLyrics extends StatelessWidget {
  const _ImmersiveLyrics();

  /// 固定高度，按"三行都是单行文本 + 单行翻译"的常见情况留出富余量。
  ///
  /// **必须固定，不能跟着内容变。** 歌词是异步到达的：切歌那一刻这里先是
  /// 0 行（还没加载），几十到几百毫秒后变成 3 行。如果高度跟着内容走，上下
  /// 的 [Spacer] 会在歌词到达的那一帧重新分配空间，封面和标题就会跟着上下
  /// 弹一下——这正是"切歌时封面先掉下去再弹回来"的成因。固定高度之后，
  /// 加载中这里是一片空白，词到了才在原地淡入，周围的布局全程不动。
  static const double _height = 168;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      // 极端情况下（三行都因为超长被迫换行到 2 行）内容可能撑破这个高度；
      // 裁掉多出来的部分，不让它把周围布局重新顶起来——静默裁切好过布局
      // 抖动，这类超长行本来就不常见。
      child: ClipRect(
        child: Watch.builder(
          builder: (context) {
            final lyrics = LyricsService.instance;
            final snap = lyrics.snapshotSignal.value;
            final model = lyrics.lyricModelSignal.value;
            final lines = model?.lines ?? const <LyricLine>[];
            final scheme = Theme.of(context).colorScheme;

            final List<Widget> rows;
            if (snap.status == LyricsLoadStatus.loading && lines.isEmpty) {
              rows = const [];
            } else if (lines.isEmpty) {
              rows = [
                Text(
                  '暂无歌词',
                  style: AppTypography.bodyLg.on(
                    scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ];
            } else {
              final active = lyrics.activeIndexSignal.value;
              final base = (active >= 0 && active < lines.length) ? active : 0;
              rows = [
                for (var offset = -1; offset <= 1; offset++)
                  _LyricRow(
                    line: (base + offset >= 0 && base + offset < lines.length)
                        ? lines[base + offset]
                        : null,
                    active: offset == 0,
                  ),
              ];
            }

            return Padding(
              padding: AppSpacing.page,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: rows,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({required this.line, required this.active});

  final LyricLine? line;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final current = line;
    if (current == null || current.text.trim().isEmpty) {
      return AppSpacing.gapMd;
    }
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurface.withValues(alpha: active ? 0.96 : 0.4);
    final translation = (current.translation ?? '').trim();
    final style = (active ? AppTypography.section : AppTypography.bodyLg)
        .on(color)
        .copyWith(fontWeight: active ? FontWeight.w700 : FontWeight.w500);

    return Padding(
      padding: AppSpacing.lyricRow,
      child: Column(
        children: [
          Text(
            current.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          if (translation.isNotEmpty)
            Text(
              translation,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 控制区

class _ImmersiveControls extends StatelessWidget {
  const _ImmersiveControls({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Watch.builder(
      builder: (context) {
        final playing = player.isPlayingSignal.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: AppSpacing.xl,
              color: color,
              icon: const Icon(AppIcons.repeat),
              onPressed: player.cyclePlaybackMode,
            ),
            IconButton(
              iconSize: AppSpacing.xxl,
              color: color,
              icon: const Icon(AppIconsFilled.skipPrevious),
              onPressed: player.previous,
            ),
            IconButton(
              iconSize: AppSpacing.playGlyph,
              color: color,
              icon: Icon(playing ? AppIconsFilled.pause : AppIconsFilled.play),
              onPressed: player.togglePlayPause,
            ),
            IconButton(
              iconSize: AppSpacing.xxl,
              color: color,
              icon: const Icon(AppIconsFilled.skipNext),
              onPressed: player.next,
            ),
            IconButton(
              iconSize: AppSpacing.xl,
              color: color,
              icon: const Icon(AppIcons.queue),
              onPressed: () => showPlayerPlaylistSheet(context, player),
            ),
          ],
        );
      },
    );
  }
}

class _QueueIndicator extends StatelessWidget {
  const _QueueIndicator({required this.player});

  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final total = player.queueSignal.value.length;
        if (total == 0) return const SizedBox.shrink();
        final index = player.currentIndexSignal.value;
        final position = index >= 0 && index < total ? index + 1 : 1;
        return Text(
          '$position/$total',
          style: AppTypography.bodyLg.on(
            scheme.onSurface.withValues(alpha: 0.7),
          ),
        );
      },
    );
  }
}
