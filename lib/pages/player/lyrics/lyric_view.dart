import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart' as fl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

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

class _PlayerLyricsViewState extends State<PlayerLyricsView> with SignalsMixin {
  static const String _prefsFontSize = 'lyrics_view_font_size';
  static const String _prefsActiveFontSize = 'lyrics_view_active_font_size';
  static const String _prefsLineGap = 'lyrics_view_line_gap';
  static const String _prefsAlignment = 'lyrics_view_alignment';
  static const String _prefsShowTranslation = 'lyrics_view_show_translation';
  static const String _prefsDragToSeek = 'lyrics_view_drag_to_seek';
  static const String _prefsDragLyrics = 'lyrics_view_drag_lyrics';
  static const String _prefsDragSeek = 'lyrics_view_drag_seek';
  static const String _prefsForceKaraoke = 'lyrics_view_force_karaoke';
  static const String _prefsMiniEnabled = 'mini_lyrics_enabled';
  static const String _prefsMiniAlignment = 'mini_lyrics_alignment';

  late final _showTranslation = createSignal(true);
  late final _dragLyrics = createSignal(true);
  late final _dragSeek = createSignal(true);
  late final _forceKaraoke = createSignal(false);
  late final _miniEnabled = createSignal(true);
  late final _miniAlignment = createSignal('center');
  late final _fontSize = createSignal(16.0);
  late final _activeFontSize = createSignal(20.0);
  late final _lineGap = createSignal(14.0);
  late final _alignment = createSignal('center');
  late final _selectionCentered = createSignal(false);
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
      _selectionCentered.value = true;
    });
    _unregisterStopSelection = controller.registerEvent(LyricEvent.stopSelection, (_) {
      if (!mounted) return;
      _selectionCentered.value = false;
    });
  }

  @override
  void dispose() {
    final controller = LyricsService.instance.controller;
    controller.selectedIndexNotifier.removeListener(_onSelectionIndexChange);
    controller.isSelectingNotifier.removeListener(_onSelectingChange);
    _unregisterResumeSelectedLine?.call();
    _unregisterStopSelection?.call();
    super.dispose();
  }

  void _onSelectionIndexChange() {
    _selectionCentered.value = false;
  }

  void _onSelectingChange() {
    if (!LyricsService.instance.controller.isSelectingNotifier.value) {
      _selectionCentered.value = false;
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _showTranslation.value = prefs.getBool(_prefsShowTranslation) ?? true;
    final legacyDrag = prefs.getBool(_prefsDragToSeek);
    _dragLyrics.value =
        prefs.getBool(_prefsDragLyrics) ?? legacyDrag ?? true;
    _dragSeek.value = prefs.getBool(_prefsDragSeek) ?? legacyDrag ?? true;
    _forceKaraoke.value = prefs.getBool(_prefsForceKaraoke) ?? false;
    _miniEnabled.value = prefs.getBool(_prefsMiniEnabled) ?? true;
    _miniAlignment.value =
        prefs.getString(_prefsMiniAlignment) ?? 'center';
    _fontSize.value = prefs.getDouble(_prefsFontSize) ?? 16;
    _activeFontSize.value = prefs.getDouble(_prefsActiveFontSize) ?? 20;
    _lineGap.value = prefs.getDouble(_prefsLineGap) ?? 14;
    _alignment.value = prefs.getString(_prefsAlignment) ?? 'center';
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
    switch (_alignment.value) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  CrossAxisAlignment _contentAlignment() {
    switch (_alignment.value) {
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
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          snap: true,
          builder: (context, scrollController) {
            return Watch.builder(
              builder: (context) {
                final fontSize = _fontSize.value;
                final activeFontSize = _activeFontSize.value;
                final lineGap = _lineGap.value;
                final alignment = _alignment.value;
                final dragLyrics = _dragLyrics.value;
                final dragSeek = _dragSeek.value;
                final forceKaraoke = _forceKaraoke.value;
                final miniEnabled = _miniEnabled.value;
                final miniAlignment = _miniAlignment.value;
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
                              value: fontSize,
                              min: 14.0,
                              max: 32.0,
                              divisions: 9,
                              valueText: fontSize.toStringAsFixed(0),
                              onChanged: (v) => _fontSize.value = v,
                              onChangeEnd: (v) =>
                                  _setPrefDouble(_prefsFontSize, v),
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            ),
                            LabeledSlider(
                              title: '播放字号',
                              value: activeFontSize,
                              min: 16.0,
                              max: 48.0,
                              divisions: 16,
                              valueText: activeFontSize.toStringAsFixed(0),
                              onChanged: (v) => _activeFontSize.value = v,
                              onChangeEnd: (v) =>
                                  _setPrefDouble(_prefsActiveFontSize, v),
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            ),
                            LabeledSlider(
                              title: '行距',
                              value: lineGap,
                              min: 8.0,
                              max: 32.0,
                              divisions: 12,
                              valueText: lineGap.toStringAsFixed(0),
                              onChanged: (v) => _lineGap.value = v,
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
                                  selected: {alignment},
                                  onSelectionChanged: (selection) {
                                    final v = selection.first;
                                    _alignment.value = v;
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
                          showDividers: false,
                          children: [
                            AppSettingSwitchTile(
                              title: '拖动歌词',
                              value: dragLyrics,
                              onChanged: (v) {
                                _dragLyrics.value = v;
                                _setPrefBool(_prefsDragLyrics, v);
                              },
                            ),
                            if (dragLyrics)
                              AppSettingSwitchTile(
                                title: '拖动调节进度',
                                value: dragSeek,
                                onChanged: (v) {
                                  _dragSeek.value = v;
                                  _setPrefBool(_prefsDragSeek, v);
                                },
                              ),
                            AppSettingSwitchTile(
                              title: '强制逐字',
                              subtitle: '对非逐字歌词进行逐字处理',
                              value: forceKaraoke,
                              onChanged: (v) async {
                                _forceKaraoke.value = v;
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
                          showDividers: false,
                          children: [
                            AppSettingSwitchTile(
                              title: '显示三行歌词',
                              value: miniEnabled,
                              onChanged: (v) {
                                _miniEnabled.value = v;
                                _setPrefBool(_prefsMiniEnabled, v);
                              },
                            ),
                            if (miniEnabled)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                                    selected: {miniAlignment},
                                    onSelectionChanged: (selection) {
                                      final v = selection.first;
                                      _miniAlignment.value = v;
                                      _setPrefString(_prefsMiniAlignment, v);
                                    },
                                    showSelectedIcon: false,
                                  ),
                                ),
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

    return Watch.builder(
      builder: (context) {
        final dragLyrics = _dragLyrics.value;
        final dragSeek = _dragSeek.value;
        final showTranslation = _showTranslation.value;
        final forceKaraoke = _forceKaraoke.value;
        final fontSize = _fontSize.value;
        final activeFontSize = _activeFontSize.value;
        final lineGap = _lineGap.value;
        final snap = lyrics.snapshotSignal.value;
        final isPlaying = player.isPlayingSignal.value;
        final model = lyrics.lyricModelSignal.value;
        final selecting = lyrics.isSelectingSignal.value;
        final centered = _selectionCentered.value;
        final index = lyrics.selectedIndexSignal.value;
        final hasTranslation = model?.lines.any(
              (l) => (l.translation ?? '').trim().isNotEmpty,
            ) ??
            false;

        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: LyricsDragToSeek(
                    enabled: dragLyrics,
                    player: player,
                    lyrics: lyrics,
                    child: () {
                      final hasLines = model?.lines.isNotEmpty ?? false;
                      if (snap.status == LyricsLoadStatus.loading && !hasLines) {
                        return const SizedBox.shrink();
                      }
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
                      final karaokeMode = forceKaraoke || hasKaraokeWords;
                      final isLight = theme.brightness == Brightness.light;
                      final inactiveColor = isLight
                          ? const Color(0xFF8C8C8C)
                          : onSurface.withValues(alpha: 0.45);
                      final activeColor = isLight ? Colors.black : onSurface;
                      final highlightColor = isLight ? Colors.black : onSurface;
                      final karaokeBaseColor = inactiveColor;

                      final translationStyle = showTranslation
                          ? TextStyle(
                              color: isLight
                                  ? const Color(0xFF7A7A7A)
                                  : onSurface.withValues(alpha: 0.35),
                              fontSize: fontSize * 0.85,
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
                          fontSize: fontSize,
                          height: 1.3,
                        ),
                        activeStyle: TextStyle(
                          color: karaokeMode ? karaokeBaseColor : activeColor,
                          fontSize: activeFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                        translationStyle: translationStyle,
                        translationActiveColor: showTranslation
                            ? onSurface.withValues(alpha: 0.9)
                            : Colors.transparent,
                        lineTextAlign: _lineTextAlign(),
                        contentAlignment: _contentAlignment(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        lineGap: lineGap,
                        translationLineGap: showTranslation ? 8 : 0,
                        selectionAnchorPosition: 0.5,
                        activeAnchorPosition: 0.5,
                        selectionAlignment: MainAxisAlignment.center,
                        activeAlignment: MainAxisAlignment.center,
                        scrollDuration: const Duration(milliseconds: 160),
                        selectedColor: activeColor,
                        selectedTranslationColor:
                            onSurface.withValues(alpha: 0.9),
                        selectionAutoResumeDuration:
                            const Duration(milliseconds: 200),
                        activeAutoResumeDuration: isPlaying
                            ? const Duration(seconds: 3)
                            : const Duration(days: 365),
                        disableTouchEvent: !dragLyrics,
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
                          if (!dragLyrics || !selecting)
                            const SizedBox.shrink()
                          else
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: SizedBox(
                                  height: 44,
                                  child: () {
                                    final m = model;
                                    final showDetails =
                                        index >= 0 && index < m.lines.length;
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
                                              fontWeight: FontWeight.w500,
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
                                        if (showDetails && dragSeek)
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (index < 0 ||
                                                  index >= m.lines.length) {
                                                return;
                                              }
                                              final start =
                                                  m.lines[index].start;
                                              lyrics.controller.stopSelection();
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
                                  }(),
                                ),
                              ),
                            ),
                        ],
                      );
                    }(),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: LyricsActionsBar(
                hasTranslation: hasTranslation,
                showTranslation: showTranslation,
                onOpenSettings: _openLyricsSettingsSheet,
                onToggleTranslation: () {
                  _showTranslation.value = !showTranslation;
                  _setPrefBool(_prefsShowTranslation, _showTranslation.value);
                },
                color: onSurface,
              ),
            ),
          ],
        );
      },
    );
  }
}

