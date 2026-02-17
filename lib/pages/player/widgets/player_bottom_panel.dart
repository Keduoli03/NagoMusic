import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/settings_state.dart';
import '../../../components/common/app_list_tile.dart';
import '../../../components/common/labeled_slider.dart';
import '../../../components/feedback/app_toast.dart';
import '../../library/library_detail_pages.dart';
import '../../songs/song_detail_sheet.dart';
import 'player_background.dart';

class PlayerBottomPanel extends StatelessWidget {
  final PlayerService player;
  final VoidCallback onTapLyrics;

  const PlayerBottomPanel({
    super.key,
    required this.player,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    PlayerBottomActionSettings.ensureLoaded();
    return Column(
      children: [
        _MiniLyricsPreview(onTap: onTapLyrics),
        _PlayerSeekBar(player: player),
        const SizedBox(height: 20),
        _PlayerControls(player: player),
        const SizedBox(height: 30),
        _BottomActions(player: player),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _MiniLyricsPreview extends StatefulWidget {
  final VoidCallback onTap;

  const _MiniLyricsPreview({required this.onTap});

  @override
  State<_MiniLyricsPreview> createState() => _MiniLyricsPreviewState();
}

class _MiniLyricsPreviewState extends State<_MiniLyricsPreview>
    with SignalsMixin {
  static const String _prefsMiniEnabled = 'mini_lyrics_enabled';
  static const String _prefsShowTranslation = 'lyrics_view_show_translation';
  static const String _prefsMiniAlignment = 'mini_lyrics_alignment';

  late final _enabled = createSignal(true);
  late final _showTranslation = createSignal(true);
  late final _alignment = createSignal('center');

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    LyricsService.instance.viewSettingsTick.addListener(_onSettingsTick);
  }

  @override
  void dispose() {
    LyricsService.instance.viewSettingsTick.removeListener(_onSettingsTick);
    super.dispose();
  }

  void _onSettingsTick() {
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _enabled.value = prefs.getBool(_prefsMiniEnabled) ?? true;
    _showTranslation.value = prefs.getBool(_prefsShowTranslation) ?? true;
    _alignment.value = prefs.getString(_prefsMiniAlignment) ?? 'center';
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        if (!_enabled.value) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final lyrics = LyricsService.instance;
        final active = lyrics.activeIndexSignal.value;
        final snap = lyrics.snapshotSignal.value;
        final model = lyrics.lyricModelSignal.value;
        final lines = model?.lines ?? const <LyricLine>[];
        final alignment = _alignment.value;
        final textAlign = alignment == 'left'
            ? TextAlign.left
            : alignment == 'right'
                ? TextAlign.right
                : TextAlign.center;
        final crossAlign = alignment == 'left'
            ? CrossAxisAlignment.start
            : alignment == 'right'
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center;

        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  height: 110,
                  child: Center(
                    child: () {
                      if (snap.status == LyricsLoadStatus.loading) {
                        return const SizedBox.shrink();
                      }
                      if (lines.isEmpty) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '暂无歌词',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurface.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '纯音乐或未匹配到歌词',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      }

                      final base =
                          (active >= 0 && active < lines.length) ? active : 0;
                      String lineAt(int i) {
                        if (i < 0) return '';
                        if (i >= lines.length) return '';
                        return lines[i].text;
                      }

                      String translationAt(int i) {
                        if (i < 0) return '';
                        if (i >= lines.length) return '';
                        return (lines[i].translation ?? '').trim();
                      }

                      final prev = lineAt(base - 1);
                      final curr = lineAt(base);
                      final currTrans = _showTranslation.value
                          ? translationAt(base)
                          : '';
                      final next = lineAt(base + 1);
                      final showTransLine = currTrans.isNotEmpty;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: crossAlign,
                        children: [
                          Text(
                            prev.isEmpty ? ' ' : prev,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.55),
                              fontSize: 14,
                            ),
                            textAlign: textAlign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: showTransLine ? 6 : 8),
                          Text(
                            curr.isEmpty ? ' ' : curr,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: showTransLine ? 16 : 18,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: textAlign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (showTransLine) ...[
                            const SizedBox(height: 4),
                            Text(
                              currTrans,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                              textAlign: textAlign,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          SizedBox(height: showTransLine ? 6 : 8),
                          Text(
                            next.isEmpty ? ' ' : next,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.55),
                              fontSize: 14,
                            ),
                            textAlign: textAlign,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    }(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _PlayerSeekBar extends StatefulWidget {
  final PlayerService player;

  const _PlayerSeekBar({required this.player});

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> with SignalsMixin {
  late final _dragValue = createSignal<double?>(null);

  String _format(Duration? duration) {
    final total = duration?.inSeconds ?? 0;
    if (total <= 0) return '00:00';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final position = widget.player.positionSignal.value;
        final duration = widget.player.durationSignal.value;
        final scheme = Theme.of(context).colorScheme;
        final totalMs = duration?.inMilliseconds ?? 0;
        final max = totalMs <= 0 ? 1.0 : totalMs.toDouble();
        final currentMs =
            position.inMilliseconds.clamp(0, max.toInt()).toInt();
        final sliderValue = _dragValue.value ?? currentMs.toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: scheme.onSurface,
                  inactiveTrackColor:
                      scheme.onSurfaceVariant.withValues(alpha: 0.25),
                  thumbColor: scheme.onSurface,
                ),
                child: Slider(
                  value: sliderValue.clamp(0, max).toDouble(),
                  min: 0,
                  max: max,
                  onChanged: totalMs <= 0
                      ? null
                      : (value) => _dragValue.value = value,
                  onChangeEnd: totalMs <= 0
                      ? null
                      : (value) {
                          _dragValue.value = null;
                          widget.player.seek(
                            Duration(milliseconds: value.round()),
                          );
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _format(Duration(milliseconds: currentMs)),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      _format(duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final PlayerService player;

  const _PlayerControls({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = scheme.onSurface;
    final iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Watch.builder(
      builder: (context) {
        final playing = player.isPlayingSignal.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_previous_rounded, color: iconColor),
              onPressed: player.previous,
            ),
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
              ),
              child: IconButton(
                iconSize: 64,
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: titleColor,
                ),
                onPressed: player.togglePlayPause,
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_next_rounded, color: iconColor),
              onPressed: player.next,
            ),
          ],
        );
      },
    );
  }
}

class _BottomActions extends StatelessWidget {
  final PlayerService player;

  const _BottomActions({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Watch.builder(
      builder: (context) {
        final mode = player.playbackModeSignal.value;
        final text = player.sleepTimerDisplayTextSignal.value;
        final icon = switch (mode) {
          PlaybackMode.shuffle => Icons.shuffle,
          PlaybackMode.loop => Icons.repeat,
          PlaybackMode.single => Icons.repeat_one,
        };
        return AnimatedBuilder(
          animation: Listenable.merge([
            PlayerBottomActionSettings.showPlaybackMode,
            PlayerBottomActionSettings.showSleepTimer,
            PlayerBottomActionSettings.showPlaylist,
            PlayerBottomActionSettings.showMore,
            PlayerBottomActionSettings.actionOrder,
          ]),
          builder: (context, _) {
            final actions = <Widget>[];
            final order = PlayerBottomActionSettings.actionOrder.value;
            for (final key in order) {
              switch (key) {
                case 'playback_mode':
                  if (PlayerBottomActionSettings.showPlaybackMode.value) {
                    actions.add(
                      IconButton(
                        icon: Icon(icon, color: iconColor),
                        onPressed: player.cyclePlaybackMode,
                      ),
                    );
                  }
                  break;
                case 'sleep_timer':
                  if (PlayerBottomActionSettings.showSleepTimer.value) {
                    actions.add(
                      Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            icon: Icon(Icons.alarm, color: iconColor),
                            onPressed: () => _showSleepTimerSheet(context),
                          ),
                          if (text != null)
                            Positioned(
                              bottom: -8,
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: iconColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }
                  break;
                case 'playlist':
                  if (PlayerBottomActionSettings.showPlaylist.value) {
                    actions.add(
                      IconButton(
                        icon: Icon(
                          Icons.format_list_bulleted,
                          color: iconColor,
                        ),
                        onPressed: () => _showPlaylistSheet(context),
                      ),
                    );
                  }
                  break;
                default:
                  if (PlayerBottomActionSettings.showMore.value) {
                    actions.add(
                      IconButton(
                        icon: Icon(Icons.more_horiz, color: iconColor),
                        onPressed: () => _showSongDetailSheet(context),
                      ),
                    );
                  }
                  break;
              }
            }
            if (actions.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: actions,
              ),
            );
          },
        );
      },
    );
  }

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SleepTimerSheet(player: player),
    );
  }

  void _showPlaylistSheet(BuildContext context) {
    showPlayerPlaylistSheet(context, player);
  }

  void _showSongDetailSheet(BuildContext context) {
    final song = player.currentSong.value;
    if (song == null) {
      AppToast.show(context, '暂无歌曲');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SongDetailSheet(
        song: song,
        onOpenArtist: (artistName) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArtistDetailPage(artistName: artistName),
            ),
          );
        },
        onOpenAlbum: (albumName) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AlbumDetailPage(albumName: albumName),
            ),
          );
        },
      ),
    );
  }
}

void showPlayerPlaylistSheet(BuildContext context, PlayerService player) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlaylistSheet(player: player),
  );
}

Color _primaryTextColor(bool useDarkText) {
  return useDarkText
      ? Colors.black.withValues(alpha: 0.88)
      : Colors.white.withValues(alpha: 0.92);
}

Color _secondaryTextColor(bool useDarkText, double alpha) {
  return useDarkText
      ? Colors.black.withValues(alpha: alpha)
      : Colors.white.withValues(alpha: alpha);
}

class _PlayerSheetView extends StatelessWidget {
  final PlayerService player;
  final double height;
  final Color maskColor;
  final Color dragHandleColor;
  final Widget header;
  final Widget body;

  const _PlayerSheetView({
    required this.player,
    required this.height,
    required this.maskColor,
    required this.dragHandleColor,
    required this.header,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Stack(
          children: [
            RepaintBoundary(
              child: PlayerBackground(songSignal: player.currentSongSignal),
            ),
            RepaintBoundary(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: maskColor),
              ),
            ),
            Column(
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 32,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: dragHandleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                header,
                body,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepTimerSheet extends StatefulWidget {
  final PlayerService player;

  const _SleepTimerSheet({required this.player});

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> with SignalsMixin {
  late final _minutes = createSignal(30.0);

  @override
  void initState() {
    super.initState();
    final remaining = widget.player.sleepRemaining;
    if (remaining != null && remaining > const Duration(minutes: 1)) {
      _minutes.value = remaining.inMinutes.clamp(5, 120).toDouble();
    }
  }

  String _formatMinutes(num minutes) {
    final totalMinutes = minutes.round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '$hours:${mins.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final preferLightBackground = Theme.of(context).brightness == Brightness.light;
    final useDarkText = preferLightBackground;
    final textColor = _primaryTextColor(useDarkText);
    final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
    final maskColor = Theme.of(context).colorScheme.surface;

    final sheetHeight = MediaQuery.sizeOf(context).height * 0.4;
    return Watch.builder(
      builder: (context) {
        final minutes = _minutes.value;
        final untilSongEnd = widget.player.sleepUntilSongEndSignal.value;
        final text = widget.player.sleepTimerDisplayTextSignal.value;
        final isActive = text != null && text.isNotEmpty;
        return SafeArea(
          child: _PlayerSheetView(
            player: widget.player,
            height: sheetHeight,
            maskColor: maskColor,
            dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
            header: _SleepTimerHeader(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
            body: Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LabeledSlider(
                        title: '定时时长',
                        value: minutes,
                        min: 5,
                        max: 120,
                        divisions: 23,
                        tickCount: 24,
                        valueText: _formatMinutes(minutes),
                        label: '${minutes.round()} 分钟',
                        onChanged: (v) => _minutes.value = v,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '播完整首歌后关闭',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: textColor),
                            ),
                          ),
                          Switch.adaptive(
                            value: untilSongEnd,
                            onChanged: (value) {
                              if (value) {
                                widget.player.setSleepTimerToSongEnd();
                              } else {
                                widget.player.cancelSleepTimer();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.player.setSleepTimer(
                              Duration(minutes: minutes.round()),
                            );
                          },
                          child: const Text('开始定时'),
                        ),
                      ),
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                widget.player.cancelSleepTimer();
                              },
                              child: const Text('取消定时'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SleepTimerHeader extends StatelessWidget {
  final Color textColor;
  final Color secondaryTextColor;

  const _SleepTimerHeader({
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            height: 34,
            child: Center(
              child: Text(
                '定时',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}

class _PlaylistSheet extends StatefulWidget {
  final PlayerService player;

  const _PlaylistSheet({required this.player});

  @override
  State<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<_PlaylistSheet> {
  static const double _itemExtent = 60;
  late final ScrollController _controller;
  int _lastIndex = -1;

  double _calcOffset(int index, int length) {
    if (index <= 0 || length <= 0) return 0;
    final startIndex = (index - 2).clamp(0, length - 1);
    return startIndex * _itemExtent;
  }

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.player.currentIndexSignal.value;
    _controller = ScrollController(
      initialScrollOffset:
          _calcOffset(_lastIndex, widget.player.queueSignal.value.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preferLightBackground = Theme.of(context).brightness == Brightness.light;
    final useDarkText = preferLightBackground;
    final textColor = _primaryTextColor(useDarkText);
    final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
    final maskColor = scheme.surface;

    return Watch.builder(
      builder: (context) {
        final queue = widget.player.queueSignal.value;
        final currentIndex = widget.player.currentIndexSignal.value;
        final total = queue.length;
        final current = currentIndex >= 0 ? currentIndex + 1 : 0;
        if (currentIndex != _lastIndex && currentIndex >= 0) {
          _lastIndex = currentIndex;
          final offset = _calcOffset(_lastIndex, total);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_controller.hasClients) {
              _controller.animateTo(
                offset,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }

        final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
        return SafeArea(
          child: _PlayerSheetView(
            player: widget.player,
            height: sheetHeight,
            maskColor: maskColor,
            dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
            header: _PlaylistHeader(
              total: total,
              current: current,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              onClear: widget.player.clearQueue,
            ),
            body: Expanded(
              child: total == 0
                  ? Center(
                      child: Text(
                        '暂无歌曲',
                        style: TextStyle(color: secondaryTextColor),
                      ),
                    )
                  : RepaintBoundary(
                      child: ReorderableListView.builder(
                        scrollController: _controller,
                        itemExtent: _itemExtent,
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) {
                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, child) {
                              final animValue =
                                  Curves.easeInOut.transform(animation.value);
                              final elevation = ui.lerpDouble(0, 6, animValue)!;
                              return Material(
                                elevation: elevation,
                                color: Colors.transparent,
                                shadowColor: Colors.black.withValues(alpha: 0.3),
                                child: child,
                              );
                            },
                            child: child,
                          );
                        },
                        onReorder: (oldIndex, newIndex) {
                          widget.player.reorderQueue(oldIndex, newIndex);
                        },
                        itemCount: total,
                        itemBuilder: (context, index) {
                          final song = queue[index];
                          final isCurrent = index == currentIndex;
                          final titleColor = isCurrent ? scheme.primary : textColor;
                          final artistColor =
                              secondaryTextColor.withValues(alpha: 0.85);
                          return RepaintBoundary(
                            key: ValueKey(song.id),
                            child: AppListTile(
                              title: song.title,
                              subtitle: song.artist,
                              titleColor: titleColor,
                              subtitleColor: artistColor,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: secondaryTextColor,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      widget.player.removeFromQueue(index);
                                    },
                                  ),
                                  ReorderableDelayedDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                        right: 8,
                                      ),
                                      child: Icon(
                                        Icons.menu,
                                        color: secondaryTextColor,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                widget.player.skipToIndex(index);
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final int total;
  final int current;
  final Color textColor;
  final Color secondaryTextColor;
  final VoidCallback onClear;

  const _PlaylistHeader({
    required this.total,
    required this.current,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            height: 34,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 2,
                  child: Text(
                    '$current/$total',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    '播放队列',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 2,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerRight,
                    ),
                    onPressed: onClear,
                    child: Text(
                      '清空',
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}
