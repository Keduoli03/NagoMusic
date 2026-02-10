import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as lyric_model;
import 'package:flutter_lyric/core/lyric_style.dart';

import 'lyric_view.dart';

class LyricsViewer extends StatefulWidget {
  final String lyrics;
  final String? translation;
  final lyric_model.LyricModel? lyricModel;
  final Duration position;
  final Color dominantColor;
  final double fontSize;
  final double lineGap;
  final String alignment;
  final double activeFontSize;
  final bool enableDrag;
  final Function(Duration)? onSeek;
  final EdgeInsets? contentPadding;
  final bool showTranslationText;
  final bool isPlaying;

  const LyricsViewer({
    super.key,
    required this.lyrics,
    this.translation,
    this.lyricModel,
    required this.position,
    required this.dominantColor,
    this.fontSize = 20.0,
    this.lineGap = 14.0,
    this.alignment = 'center',
    this.activeFontSize = 26.0,
    this.enableDrag = true,
    this.onSeek,
    this.contentPadding,
    this.showTranslationText = true,
    this.isPlaying = false,
  });

  @override
  State<LyricsViewer> createState() => _LyricsViewerState();
}

class _LyricsViewerState extends State<LyricsViewer>
    with SingleTickerProviderStateMixin {
  late LyricController _controller;
  late final Ticker _ticker;
  Duration _basePosition = Duration.zero;
  int _baseTimestampMs = 0;
  int _lastExternalUpdateMs = 0;
  Duration _lastExternalPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = LyricController();
    _loadLyrics();
    _syncExternalPosition(widget.position);
    // Fix: Immediately set progress to ensure correct initial render state
    // This prevents the "normal font size" glitch when returning to a paused song
    _controller.setProgress(widget.position);
    _ticker = createTicker((_) {
      if (!widget.isPlaying) {
        _controller.setProgress(_lastExternalPosition);
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastExternalUpdateMs > 500) {
        _controller.setProgress(_lastExternalPosition);
        return;
      }
      final elapsed = now - _baseTimestampMs;
      final estimated = _basePosition +
          Duration(milliseconds: elapsed.clamp(0, 60000).toInt());
      _controller.setProgress(estimated);
    })
      ..start();
    if (widget.enableDrag && widget.onSeek != null) {
      _controller.setOnTapLineCallback((position) {
        _controller.stopSelection();
        widget.onSeek?.call(position);
      });
    }
  }

  void _loadLyrics() {
    if (widget.lyricModel != null) {
      final source = widget.lyricModel!;
      if (!widget.showTranslationText) {
        final lines = source.lines
            .map(
              (line) => lyric_model.LyricLine(
                start: line.start,
                end: line.end,
                text: line.text,
                translation: null,
                words: line.words,
              ),
            )
            .toList();
        _controller.loadLyricModel(lyric_model.LyricModel(lines: lines));
      } else {
        _controller.loadLyricModel(source);
      }
    } else if (widget.lyrics.isNotEmpty) {
      _controller.loadLyric(
        widget.lyrics,
        translationLyric: widget.showTranslationText ? widget.translation : null,
      );
    } else {
      _controller.loadLyric('');
    }
  }

  @override
  void didUpdateWidget(LyricsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyricModel != oldWidget.lyricModel ||
        widget.lyrics != oldWidget.lyrics ||
        widget.translation != oldWidget.translation ||
        widget.showTranslationText != oldWidget.showTranslationText) {
      _loadLyrics();
    }
    if (widget.enableDrag != oldWidget.enableDrag ||
        widget.onSeek != oldWidget.onSeek) {
      if (widget.enableDrag && widget.onSeek != null) {
        _controller.setOnTapLineCallback((position) {
          _controller.stopSelection();
          widget.onSeek?.call(position);
        });
      } else {
        _controller.cancelOnTapLineCallback();
      }
    }
    if (widget.position != oldWidget.position) {
      _syncExternalPosition(widget.position);
      _controller.setProgress(widget.position);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncExternalPosition(Duration position) {
    _basePosition = position;
    _lastExternalPosition = position;
    final now = DateTime.now().millisecondsSinceEpoch;
    _baseTimestampMs = now;
    _lastExternalUpdateMs = now;
  }

  @override
  Widget build(BuildContext context) {
    final hasModelLines = widget.lyricModel?.lines.isNotEmpty ?? false;
    final hasKaraokeWords = widget.lyricModel != null;
    if (!hasModelLines && widget.lyrics.trim().isEmpty) {
      return _buildEmptyState();
    }

    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    final lyricActiveColor =
        isLightMode ? Colors.black : Colors.white;
    final lyricInactiveColor =
        isLightMode ? const Color(0xFF8C8C8C) : Colors.white.withValues(alpha: 0.6);
    final highlightColor = isLightMode ? Colors.black : theme.colorScheme.primary;

    final align = switch (widget.alignment) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };

    final crossAlign = switch (widget.alignment) {
      'left' => CrossAxisAlignment.start,
      'right' => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };

    final mainAlign = switch (widget.alignment) {
      'left' => MainAxisAlignment.start,
      'right' => MainAxisAlignment.end,
      _ => MainAxisAlignment.center,
    };

    final style = _buildStyle(
      lyricActiveColor: isLightMode ? lyricActiveColor : Colors.white,
      lyricInactiveColor: lyricInactiveColor,
      highlightColor: highlightColor,
      align: align,
      crossAlign: crossAlign,
      mainAlign: mainAlign,
      hasKaraokeWords: hasKaraokeWords,
    );

    return Stack(
      children: [
        LyricView(
          controller: _controller,
          style: style,
          width: double.infinity,
          height: double.infinity,
          showTranslationText: widget.showTranslationText,
        ),
      ],
    );
  }

  LyricStyle _buildStyle({
    required Color lyricActiveColor,
    required Color lyricInactiveColor,
    required Color highlightColor,
    required TextAlign align,
    required CrossAxisAlignment crossAlign,
    required MainAxisAlignment mainAlign,
    required bool hasKaraokeWords,
  }) {
    return LyricStyle(
      textStyle: TextStyle(
        color: lyricInactiveColor,
        fontSize: widget.fontSize,
      ),
      activeStyle: TextStyle(
        color: hasKaraokeWords ? lyricInactiveColor : lyricActiveColor,
        fontSize: widget.activeFontSize,
        fontWeight: FontWeight.bold,
      ),
      translationStyle: TextStyle(
        color: lyricInactiveColor.withValues(alpha: 0.8),
        fontSize: widget.fontSize * 0.8,
      ),
      lineGap: widget.lineGap,
      translationLineGap: widget.lineGap / 2,
      lineTextAlign: align,
      contentPadding: widget.contentPadding ??
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      contentAlignment: crossAlign,
      selectionAnchorPosition: 0.5,
      activeAnchorPosition: 0.5,
      scrollDuration: const Duration(milliseconds: 160),
      selectionAlignment: mainAlign,
      selectedColor: lyricActiveColor,
      selectedTranslationColor: lyricInactiveColor.withValues(alpha: 0.85),
      translationActiveColor: lyricActiveColor,
      selectionAutoResumeDuration: const Duration(milliseconds: 200),
      activeAutoResumeDuration: const Duration(seconds: 3),
      disableTouchEvent: false,
      // Disable switch animation to fix font size instability (user reported "small font" bug)
      enableSwitchAnimation: false,
      activeHighlightGradient: hasKaraokeWords
          ? LinearGradient(
              colors: [
                highlightColor.withValues(alpha: 1.0),
                highlightColor.withValues(alpha: 1.0),
              ],
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    final useDarkText = widget.dominantColor.computeLuminance() >= 0.6;
    final titleColor = useDarkText ? const Color(0xFF1B1B1B) : Colors.white;
    final lyricInactiveColor = titleColor.withValues(alpha: 0.6);
    final lyricTranslationColor = titleColor.withValues(alpha: 0.5);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '暂无歌词',
            style: TextStyle(
              color: lyricInactiveColor,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '纯音乐或未匹配到歌词',
            style: TextStyle(
              color: lyricTranslationColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
