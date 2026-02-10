import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart' as fl;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/player_service.dart';
import '../../../components/index.dart';
import 'widgets/lyrics_actions_bar.dart';
import 'widgets/lyrics_drag_to_seek.dart';

class PlayerLyricsView extends StatefulWidget {
  const PlayerLyricsView({super.key});

  @override
  State<PlayerLyricsView> createState() => _PlayerLyricsViewState();
}

class _PlayerLyricsViewState extends State<PlayerLyricsView> {
  static const String _prefsFontSize = 'lyrics_view_font_size';
  static const String _prefsActiveFontSize = 'lyrics_view_active_font_size';
  static const String _prefsLineGap = 'lyrics_view_line_gap';
  static const String _prefsAlignment = 'lyrics_view_alignment';
  static const String _prefsShowTranslation = 'lyrics_view_show_translation';
  static const String _prefsDragToSeek = 'lyrics_view_drag_to_seek';
  static const String _prefsForceKaraoke = 'lyrics_view_force_karaoke';
  static const String _prefsMiniEnabled = 'mini_lyrics_enabled';

  bool _showTranslation = true;
  bool _dragToSeek = true;
  bool _forceKaraoke = false;
  bool _miniEnabled = true;
  double _fontSize = 16;
  double _activeFontSize = 20;
  double _lineGap = 14;
  String _alignment = 'center';
  final _selectionCenteredNotifier = ValueNotifier(false);
  VoidCallback? _unregisterResumeSelectedLine;
  VoidCallback? _unregisterStopSelection;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    final controller = LyricsService.instance.controller;
    controller.selectedIndexNotifier.addListener(_onSelectionIndexChange);
    controller.isSelectingNotifier.addListener(_onSelectingChange);
    _unregisterResumeSelectedLine =
        controller.registerEvent(LyricEvent.resumeSelectedLine, (_) {
      if (!mounted) return;
      _selectionCenteredNotifier.value = true;
    });
    _unregisterStopSelection = controller.registerEvent(LyricEvent.stopSelection, (_) {
      if (!mounted) return;
      _selectionCenteredNotifier.value = false;
    });
  }

  @override
  void dispose() {
    final controller = LyricsService.instance.controller;
    controller.selectedIndexNotifier.removeListener(_onSelectionIndexChange);
    controller.isSelectingNotifier.removeListener(_onSelectingChange);
    _unregisterResumeSelectedLine?.call();
    _unregisterStopSelection?.call();
    _selectionCenteredNotifier.dispose();
    super.dispose();
  }

  void _onSelectionIndexChange() {
    _selectionCenteredNotifier.value = false;
  }

  void _onSelectingChange() {
    if (!LyricsService.instance.controller.isSelectingNotifier.value) {
      _selectionCenteredNotifier.value = false;
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showTranslation = prefs.getBool(_prefsShowTranslation) ?? true;
      _dragToSeek = prefs.getBool(_prefsDragToSeek) ?? true;
      _forceKaraoke = prefs.getBool(_prefsForceKaraoke) ?? false;
      _miniEnabled = prefs.getBool(_prefsMiniEnabled) ?? true;
      _fontSize = prefs.getDouble(_prefsFontSize) ?? 16;
      _activeFontSize = prefs.getDouble(_prefsActiveFontSize) ?? 20;
      _lineGap = prefs.getDouble(_prefsLineGap) ?? 14;
      _alignment = prefs.getString(_prefsAlignment) ?? 'center';
    });
  }

  Future<void> _setPrefBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _setPrefDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _setPrefString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  TextAlign _lineTextAlign() {
    switch (_alignment) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  CrossAxisAlignment _contentAlignment() {
    switch (_alignment) {
      case 'left':
        return CrossAxisAlignment.start;
      case 'right':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  void _openLyricsSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          snap: true,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return AppSheetPanel(
                  title: '歌词设置',
                  expand: true,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    AppSettingSection(
                      title: '样式',
                      showDividers: false,
                      children: [
                        LabeledSlider(
                          title: '字号',
                          value: _fontSize,
                          min: 14.0,
                          max: 32.0,
                          divisions: 9,
                          valueText: _fontSize.toStringAsFixed(0),
                          onChanged: (v) {
                            setSheetState(() => _fontSize = v);
                            setState(() => _fontSize = v);
                          },
                          onChangeEnd: (v) => _setPrefDouble(_prefsFontSize, v),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        ),
                        LabeledSlider(
                          title: '播放字号',
                          value: _activeFontSize,
                          min: 16.0,
                          max: 48.0,
                          divisions: 16,
                          valueText: _activeFontSize.toStringAsFixed(0),
                          onChanged: (v) {
                            setSheetState(() => _activeFontSize = v);
                            setState(() => _activeFontSize = v);
                          },
                          onChangeEnd: (v) =>
                              _setPrefDouble(_prefsActiveFontSize, v),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        ),
                        LabeledSlider(
                          title: '行距',
                          value: _lineGap,
                          min: 8.0,
                          max: 32.0,
                          divisions: 12,
                          valueText: _lineGap.toStringAsFixed(0),
                          onChanged: (v) {
                            setSheetState(() => _lineGap = v);
                            setState(() => _lineGap = v);
                          },
                          onChangeEnd: (v) => _setPrefDouble(_prefsLineGap, v),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'left',
                                  label: Text('居左'),
                                  icon: Icon(Icons.format_align_left),
                                ),
                                ButtonSegment(
                                  value: 'center',
                                  label: Text('居中'),
                                  icon: Icon(Icons.format_align_center),
                                ),
                                ButtonSegment(
                                  value: 'right',
                                  label: Text('居右'),
                                  icon: Icon(Icons.format_align_right),
                                ),
                              ],
                              selected: {_alignment},
                              onSelectionChanged: (selection) {
                                final v = selection.first;
                                setSheetState(() => _alignment = v);
                                setState(() => _alignment = v);
                                _setPrefString(_prefsAlignment, v);
                              },
                              showSelectedIcon: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppSettingSection(
                      title: '交互',
                      children: [
                        AppSettingSwitchTile(
                          title: '拖动调节进度',
                          value: _dragToSeek,
                          onChanged: (v) {
                            setSheetState(() => _dragToSeek = v);
                            setState(() => _dragToSeek = v);
                            _setPrefBool(_prefsDragToSeek, v);
                          },
                        ),
                        AppSettingSwitchTile(
                          title: '强制逐字',
                          subtitle: '对非逐字歌词进行逐字处理',
                          value: _forceKaraoke,
                          onChanged: (v) async {
                            setSheetState(() => _forceKaraoke = v);
                            setState(() => _forceKaraoke = v);
                            await _setPrefBool(_prefsForceKaraoke, v);
                            await LyricsService.instance.refreshSettings();
                            LyricsService.instance.reloadCurrentSong();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppSettingSection(
                      title: '三行歌词',
                      children: [
                        AppSettingSwitchTile(
                          title: '显示三行歌词',
                          value: _miniEnabled,
                          onChanged: (v) {
                            setSheetState(() => _miniEnabled = v);
                            _setPrefBool(_prefsMiniEnabled, v);
                          },
                        ),
                      ],
                    ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final player = PlayerService.instance;
    final lyrics = LyricsService.instance;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LyricsDragToSeek(
                enabled: _dragToSeek,
                player: player,
                lyrics: lyrics,
                child: ValueListenableBuilder<LyricsSnapshot>(
                  valueListenable: lyrics.snapshot,
                  builder: (context, snap, child) {
                    if (snap.status == LyricsLoadStatus.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ValueListenableBuilder<bool>(
                      valueListenable: player.isPlaying,
                      builder: (context, isPlaying, child) {
                        return ValueListenableBuilder(
                          valueListenable: lyrics.controller.lyricNotifier,
                          builder: (context, model, child) {
                        final hasLines = model?.lines.isNotEmpty ?? false;
                        if (!hasLines) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '暂无歌词',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: onSurface.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '纯音乐或未匹配到歌词',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final hasKaraokeWords = model!.lines
                            .any((l) => (l.words?.isNotEmpty ?? false));
                        final karaokeMode = _forceKaraoke || hasKaraokeWords;
                        final isLight = theme.brightness == Brightness.light;
                        final inactiveColor = isLight
                            ? const Color(0xFF8C8C8C)
                            : onSurface.withValues(alpha: 0.45);
                        final activeColor = isLight ? Colors.black : onSurface;
                        final highlightColor = isLight ? Colors.black : onSurface;
                        final karaokeBaseColor = inactiveColor;

                        final translationStyle = _showTranslation
                            ? TextStyle(
                                color: isLight
                                    ? const Color(0xFF7A7A7A)
                                    : onSurface.withValues(alpha: 0.35),
                                fontSize: _fontSize * 0.85,
                                height: 1.2,
                              )
                            : const TextStyle(
                                color: Colors.transparent,
                                fontSize: 0,
                                height: 0,
                              );

                        final style = LyricStyle(
                          textStyle: TextStyle(
                            color: inactiveColor,
                            fontSize: _fontSize,
                            height: 1.3,
                          ),
                          activeStyle: TextStyle(
                            color: karaokeMode ? karaokeBaseColor : activeColor,
                            fontSize: _activeFontSize,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          translationStyle: translationStyle,
                          translationActiveColor: _showTranslation
                              ? onSurface.withValues(alpha: 0.9)
                              : Colors.transparent,
                          lineTextAlign: _lineTextAlign(),
                          contentAlignment: _contentAlignment(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          lineGap: _lineGap,
                          translationLineGap: _showTranslation ? 8 : 0,
                          selectionAnchorPosition: 0.5,
                          activeAnchorPosition: 0.5,
                          selectionAlignment: MainAxisAlignment.center,
                          activeAlignment: MainAxisAlignment.center,
                          scrollDuration: const Duration(milliseconds: 160),
                          selectedColor: activeColor,
                          selectedTranslationColor: onSurface.withValues(alpha: 0.9),
                          selectionAutoResumeDuration:
                              const Duration(milliseconds: 200),
                          activeAutoResumeDuration: isPlaying
                              ? const Duration(seconds: 3)
                              : const Duration(days: 365),
                          disableTouchEvent: !_dragToSeek,
                          enableSwitchAnimation: false,
                          activeHighlightGradient: karaokeMode
                              ? LinearGradient(
                                  colors: [
                                    highlightColor.withValues(alpha: 1.0),
                                    highlightColor.withValues(alpha: 1.0),
                                  ],
                                )
                              : null,
                          activeHighlightExtraFadeWidth: 0,
                        );
                        return Stack(
                          children: [
                            fl.LyricView(
                              controller: lyrics.controller,
                              style: style,
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: lyrics.controller.isSelectingNotifier,
                              builder: (context, selecting, child) {
                                if (!_dragToSeek || !selecting) {
                                  return const SizedBox.shrink();
                                }
                                return ValueListenableBuilder<bool>(
                                  valueListenable: _selectionCenteredNotifier,
                                  builder: (context, centered, child) {
                                    return Align(
                                      alignment: Alignment.center,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        child: SizedBox(
                                          height: 44,
                                          child: ValueListenableBuilder<int>(
                                            valueListenable: lyrics
                                                .controller.selectedIndexNotifier,
                                            builder: (context, index, child) {
                                              final m = lyrics
                                                  .controller.lyricNotifier.value;
                                              final showDetails = m != null &&
                                                  index >= 0 &&
                                                  index < m.lines.length;
                                              final timeText = showDetails
                                                  ? "${m.lines[index].start.inMinutes.toString().padLeft(2, '0')}:${(m.lines[index].start.inSeconds % 60).toString().padLeft(2, '0')}"
                                                  : '';
                                              return Row(
                                                children: [
                                                  if (showDetails)
                                                    Text(
                                                      timeText,
                                                      style: TextStyle(
                                                        color: activeColor,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  if (showDetails)
                                                    const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Container(
                                                      height: 1,
                                                      color: centered
                                                          ? Colors.transparent
                                                          : onSurface.withValues(
                                                              alpha: 0.25),
                                                    ),
                                                  ),
                                                  if (showDetails)
                                                    const SizedBox(width: 8),
                                                  if (showDetails)
                                                    GestureDetector(
                                                      behavior:
                                                          HitTestBehavior.opaque,
                                                      onTap: () {
                                                        final cur = lyrics
                                                            .controller
                                                            .lyricNotifier
                                                            .value;
                                                        if (cur == null ||
                                                            index < 0 ||
                                                            index >=
                                                                cur.lines.length) {
                                                          return;
                                                        }
                                                        final start =
                                                            cur.lines[index].start;
                                                        lyrics.controller
                                                            .stopSelection();
                                                        player.seek(start);
                                                      },
                                                      child: Icon(
                                                        Icons.play_arrow_rounded,
                                                        size: 32,
                                                        color: activeColor,
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: ValueListenableBuilder(
            valueListenable: lyrics.controller.lyricNotifier,
            builder: (context, model, child) {
              final hasTranslation = model?.lines.any(
                    (l) => (l.translation ?? '').trim().isNotEmpty,
                  ) ??
                  false;
              return LyricsActionsBar(
                hasTranslation: hasTranslation,
                showTranslation: _showTranslation,
                onOpenSettings: _openLyricsSettingsSheet,
                onToggleTranslation: () => setState(() {
                  _showTranslation = !_showTranslation;
                  _setPrefBool(_prefsShowTranslation, _showTranslation);
                }),
                color: onSurface,
              );
            },
          ),
        ),
      ],
    );
  }
}

