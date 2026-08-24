import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/services/song_download_service.dart';
import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/state/song_state.dart';
import '../../../app/theme/app_icons.dart';
import '../../../components/common/app_list_tile.dart';
import '../../../components/common/artwork_widget.dart';
import '../../../components/common/app_switch.dart';
import '../../../components/common/labeled_slider.dart';
import '../../../components/common/playing_bars.dart';
import '../../../components/common/sheet_panels.dart';
import '../../../components/feedback/app_toast.dart';
import 'player_background.dart';
import '../../../app/utils/format_utils.dart';
import '../../library/playlist_picker_sheet.dart';
import '../../songs/song_detail_sheet.dart';
import '../../songs/show_song_detail_sheet.dart';

class PlayerBottomPanel extends StatelessWidget {
  final PlayerService player;
  final PlayerStylePreset stylePreset;
  final VoidCallback onTapLyrics;
  final bool showMiniLyrics;

  const PlayerBottomPanel({
    super.key,
    required this.player,
    required this.stylePreset,
    required this.onTapLyrics,
    this.showMiniLyrics = true,
  });

  @override
  Widget build(BuildContext context) {
    PlayerBottomActionSettings.ensureLoaded();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomSpacing = bottomInset > 20 ? bottomInset + 16.0 : 30.0;
    return Column(
      children: [
        if (showMiniLyrics)
          _MiniLyricsPreview(onTap: onTapLyrics, stylePreset: stylePreset),
        _PlayerSeekBar(player: player, stylePreset: stylePreset),
        const SizedBox(height: 20),
        _PlayerControls(player: player),
        const SizedBox(height: 30),
        _BottomActions(player: player),
        SizedBox(height: bottomSpacing),
      ],
    );
  }
}

class _MiniLyricsPreview extends StatefulWidget {
  final VoidCallback onTap;
  final PlayerStylePreset stylePreset;

  const _MiniLyricsPreview({required this.onTap, required this.stylePreset});

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
        final previewHeight = switch (widget.stylePreset) {
          PlayerStylePreset.poster => 118.0,
          PlayerStylePreset.classic => 110.0,
        };
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
                  height: previewHeight,
                  child: Center(
                    child: () {
                      // While loading a new song's lyrics, keep the area blank
                      // (no skeleton) — show the real lines as soon as they
                      // arrive. If lyrics are already present, keep showing them.
                      if (snap.status == LyricsLoadStatus.loading &&
                          lines.isEmpty) {
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
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        );
                      }

                      final base = (active >= 0 && active < lines.length)
                          ? active
                          : 0;
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
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
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
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.55,
                                ),
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
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
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
  final PlayerStylePreset stylePreset;

  const _PlayerSeekBar({required this.player, required this.stylePreset});

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> with SignalsMixin {
  late final _dragValue = createSignal<double?>(null);

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final position = widget.player.positionSignal.value;
        final duration = widget.player.durationSignal.value;
        final scheme = Theme.of(context).colorScheme;
        final trackHeight = switch (widget.stylePreset) {
          PlayerStylePreset.poster => 4.0,
          PlayerStylePreset.classic => 2.0,
        };
        final totalMs = duration?.inMilliseconds ?? 0;
        final max = totalMs <= 0 ? 1.0 : totalMs.toDouble();
        final currentMs = position.inMilliseconds.clamp(0, max.toInt()).toInt();
        final sliderValue = _dragValue.value ?? currentMs.toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: trackHeight,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: scheme.onSurface,
                  inactiveTrackColor: scheme.onSurfaceVariant.withValues(
                    alpha: 0.25,
                  ),
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
                      formatClock(
                        Duration(milliseconds: currentMs),
                        zeroText: '00:00',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      formatClock(duration, zeroText: '00:00'),
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
    final iconColor = scheme.onSurface;
    return Watch.builder(
      builder: (context) {
        final playing = player.isPlayingSignal.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 48,
              icon: Icon(AppIconsFilled.skipPrevious, color: iconColor),
              onPressed: player.previous,
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 56,
              icon: Icon(
                playing ? AppIconsFilled.pause : AppIconsFilled.play,
                color: iconColor,
              ),
              onPressed: player.togglePlayPause,
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 48,
              icon: Icon(AppIconsFilled.skipNext, color: iconColor),
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
    final iconColor = scheme.onSurface;
    return Watch.builder(
      builder: (context) {
        final mode = player.playbackModeSignal.value;
        final text = player.sleepTimerDisplayTextSignal.value;
        final icon = switch (mode) {
          PlaybackMode.shuffle => AppIcons.shuffle,
          PlaybackMode.loop => AppIcons.repeat,
          PlaybackMode.single => AppIcons.repeatOnce,
        };
        return AnimatedBuilder(
          animation: Listenable.merge([
            PlayerBottomActionSettings.showPlaybackMode,
            PlayerBottomActionSettings.showSleepTimer,
            PlayerBottomActionSettings.showPlaylist,
            PlayerBottomActionSettings.showAddToPlaylist,
            PlayerBottomActionSettings.showSaveToLocal,
            PlayerBottomActionSettings.showSongInfo,
            PlayerBottomActionSettings.showMore,
            PlayerBottomActionSettings.actionOrder,
          ]),
          builder: (context, _) {
            final actions = <_PlayerBottomAction>[];
            final order = PlayerBottomActionSettings.actionOrder.value;
            for (final key in order) {
              switch (key) {
                case PlayerBottomActionSettings.playbackModeKey:
                  if (PlayerBottomActionSettings.showPlaybackMode.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '播放模式',
                        icon: icon,
                        onPressed: player.cyclePlaybackMode,
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.sleepTimerKey:
                  if (PlayerBottomActionSettings.showSleepTimer.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '定时停止',
                        icon: AppIcons.alarm,
                        badge: text,
                        onPressed: () => _showSleepTimerSheet(context),
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.playlistKey:
                  if (PlayerBottomActionSettings.showPlaylist.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '播放队列',
                        icon: AppIcons.list,
                        onPressed: () => _showPlaylistSheet(context),
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.addToPlaylistKey:
                  if (PlayerBottomActionSettings.showAddToPlaylist.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '添加到歌单',
                        icon: AppIcons.addPhotos,
                        onPressed: () => _addToPlaylist(context),
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.saveToLocalKey:
                  if (PlayerBottomActionSettings.showSaveToLocal.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '保存到本地',
                        icon: AppIcons.download,
                        onPressed: () => _saveToLocal(context),
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.songInfoKey:
                  if (PlayerBottomActionSettings.showSongInfo.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '歌曲信息',
                        icon: AppIcons.info,
                        onPressed: () => _showSongInfo(context),
                      ),
                    );
                  }
                  break;
                case PlayerBottomActionSettings.moreKey:
                  if (PlayerBottomActionSettings.showMore.value) {
                    actions.add(
                      _PlayerBottomAction(
                        title: '更多',
                        icon: AppIcons.moreHorizontal,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slots = (constraints.maxWidth / 52)
                      .floor()
                      .clamp(1, 6)
                      .toInt();
                  final useOverflow = actions.length > slots;
                  final visibleCount = useOverflow ? slots - 1 : actions.length;
                  final visible = actions.take(visibleCount).toList();
                  final overflow = actions.skip(visibleCount).toList();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final action in visible)
                        action.buildButton(iconColor),
                      if (useOverflow)
                        IconButton(
                          tooltip: '更多操作',
                          icon: Icon(AppIcons.moreHorizontal, color: iconColor),
                          onPressed: () =>
                              _showOverflowSheet(context, overflow),
                        ),
                    ],
                  );
                },
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
    showSongDetailSheet(context, song: song, enablePlayerAppearanceEntry: true);
  }

  Future<void> _addToPlaylist(BuildContext context) async {
    final song = player.currentSong.value;
    if (song == null) {
      AppToast.show(context, '暂无歌曲');
      return;
    }
    await showAddToPlaylistDialog(context, songIds: [song.id]);
  }

  Future<void> _saveToLocal(BuildContext context) async {
    final song = player.currentSong.value;
    if (song == null) {
      AppToast.show(context, '暂无歌曲');
      return;
    }
    final result = await SongDownloadService.instance.saveToLocal(song);
    if (!context.mounted) return;
    AppToast.show(
      context,
      result.message,
      type: result.success ? ToastType.success : ToastType.error,
    );
  }

  void _showSongInfo(BuildContext context) {
    final song = player.currentSong.value;
    if (song == null) {
      AppToast.show(context, '暂无歌曲');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SongInfoSheet(song: song),
    );
  }

  void _showOverflowSheet(
    BuildContext context,
    List<_PlayerBottomAction> actions,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheetPanel(
        title: '更多操作',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              AppListTile(
                leading: Icon(action.icon),
                title: action.title,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action.onPressed();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerBottomAction {
  final String title;
  final IconData icon;
  final String? badge;
  final VoidCallback onPressed;

  const _PlayerBottomAction({
    required this.title,
    required this.icon,
    required this.onPressed,
    this.badge,
  });

  Widget buildButton(Color color) {
    final button = IconButton(
      tooltip: title,
      icon: Icon(icon, color: color),
      onPressed: onPressed,
    );
    if (badge == null) return button;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          bottom: -8,
          child: Text(
            badge!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
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
              child: ValueListenableBuilder<bool>(
                valueListenable: AppBackgroundSettings.glassEffectEnabled,
                builder: (context, glassEnabled, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: AppBackgroundSettings.panelBlurStrength,
                    builder: (context, blurStrength, _) {
                      final mask = Container(color: maskColor);
                      if (!glassEnabled || blurStrength <= 0) return mask;
                      return BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: blurStrength,
                          sigmaY: blurStrength,
                        ),
                        child: mask,
                      );
                    },
                  );
                },
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

  @override
  Widget build(BuildContext context) {
    final preferLightBackground =
        Theme.of(context).brightness == Brightness.light;
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
                        divisions: 115,
                        tickCount: 116,
                        valueText: formatMinutesAsClock(minutes),
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: textColor),
                            ),
                          ),
                          AppSwitch(
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
  static const double _itemExtent = 64;
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
      initialScrollOffset: _calcOffset(
        _lastIndex,
        widget.player.queueSignal.value.length,
      ),
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
    final preferLightBackground =
        Theme.of(context).brightness == Brightness.light;
    final useDarkText = preferLightBackground;
    final textColor = _primaryTextColor(useDarkText);
    final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
    final maskColor = scheme.surface;

    return Watch.builder(
      builder: (context) {
        final queue = widget.player.queueSignal.value;
        final currentIndex = widget.player.currentIndexSignal.value;
        final mode = widget.player.playbackModeSignal.value;
        final playing = widget.player.isPlayingSignal.value;
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
              mode: mode,
              accent: scheme.primary,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              onClear: widget.player.clearQueue,
              onCycleMode: widget.player.cyclePlaybackMode,
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
                              final animValue = Curves.easeInOut.transform(
                                animation.value,
                              );
                              final elevation = ui.lerpDouble(0, 6, animValue)!;
                              return Material(
                                elevation: elevation,
                                color: Colors.transparent,
                                shadowColor: Colors.black.withValues(
                                  alpha: 0.3,
                                ),
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
                          return RepaintBoundary(
                            key: ValueKey(song.id),
                            child: _QueueItem(
                              song: song,
                              index: index,
                              isCurrent: isCurrent,
                              playing: playing,
                              accent: scheme.primary,
                              textColor: textColor,
                              secondaryTextColor: secondaryTextColor,
                              onTap: () => widget.player.skipToIndex(index),
                              onRemove: () =>
                                  widget.player.removeFromQueue(index),
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
  final PlaybackMode mode;
  final Color textColor;
  final Color secondaryTextColor;
  final Color accent;
  final VoidCallback onClear;
  final VoidCallback onCycleMode;

  const _PlaylistHeader({
    required this.total,
    required this.current,
    required this.mode,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accent,
    required this.onClear,
    required this.onCycleMode,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData modeIcon, String modeLabel) = switch (mode) {
      PlaybackMode.shuffle => (AppIcons.shuffle, '随机播放'),
      PlaybackMode.single => (AppIcons.repeatOnce, '单曲循环'),
      PlaybackMode.loop => (AppIcons.repeat, '列表循环'),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '播放队列',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: onCycleMode,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 2,
                          bottom: 2,
                          right: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(modeIcon, size: 16, color: secondaryTextColor),
                            const SizedBox(width: 5),
                            Text(
                              '$modeLabel · $current/$total',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: secondaryTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(AppIcons.trash, size: 19, color: secondaryTextColor),
                label: Text(
                  '清空',
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                ),
              ),
            ],
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

/// A single row in the play-queue sheet: cover thumbnail + title/artist, with a
/// highlighted background and animated equalizer bars for the current song.
class _QueueItem extends StatelessWidget {
  final SongEntity song;
  final int index;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final Color textColor;
  final Color secondaryTextColor;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueItem({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.playing,
    required this.accent,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = isCurrent ? accent : textColor;
    final artistColor = isCurrent
        ? accent.withValues(alpha: 0.78)
        : secondaryTextColor.withValues(alpha: 0.82);
    final artist = song.artist.trim().isEmpty ? '未知艺术家' : song.artist.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isCurrent ? accent.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
            child: Row(
              children: [
                _buildCover(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title.trim().isEmpty ? '未知歌曲' : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: artistColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    AppIcons.close,
                    color: secondaryTextColor.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  onPressed: onRemove,
                ),
                ReorderableDelayedDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      AppIcons.dragHandle,
                      color: secondaryTextColor.withValues(alpha: 0.55),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    const size = 44.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ArtworkWidget(song: song, size: size, borderRadius: 8),
          if (isCurrent)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withValues(alpha: 0.38),
              ),
              child: Center(
                child: PlayingBars(color: Colors.white, animating: playing),
              ),
            ),
        ],
      ),
    );
  }
}
