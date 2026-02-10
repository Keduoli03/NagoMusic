import 'package:flutter/material.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';
import '../../utils/lyrics_parser.dart';

mixin LyricLineHighlightMixin<T extends StatefulWidget>
    on State<T>, LyricLayoutMixin<T>, TickerProviderStateMixin<T> {
  static const Duration _highlightTransitionDuration =
      Duration(milliseconds: 50);
  late final AnimationController _animationController;
  Animation<double>? _widthAnimation;
  var activeHighlightWidthNotifier = ValueNotifier(0.0);
  int? _lastActiveIndex;
  List<double>? _currentWordWidths;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: _highlightTransitionDuration,
    );
    _animationController.addListener(() {
      if (_widthAnimation != null) {
        activeHighlightWidthNotifier.value = _widthAnimation!.value;
      }
    });
    controller.activeIndexNotifiter.addListener(_onActiveIndexChange);
    controller.progressNotifier.addListener(updateHighlightWidth);
    super.initState();
  }

  void invalidateWordWidthCache() {
    _currentWordWidths = null;
    _lastActiveIndex = null;
  }

  void _onActiveIndexChange() {
    updateHighlightWidth();
  }

  @override
  void dispose() {
    controller.activeIndexNotifiter.removeListener(_onActiveIndexChange);
    controller.progressNotifier.removeListener(updateHighlightWidth);
    _animationController.dispose();
    activeHighlightWidthNotifier.dispose();
    super.dispose();
  }

  double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter.width;
  }

  void updateHighlightWidth() {
    final index = controller.activeIndexNotifiter.value;
    final metrics = layout?.metrics ?? [];
    if (index >= metrics.length || index < 0) {
      _animateWidth(0.0);
      return;
    }
    final line = metrics[index];

    // Check if we need to recalculate widths
    if (_lastActiveIndex != index) {
      _lastActiveIndex = index;
      _currentWordWidths = null;
    }

    var words = line.line.words ?? [];

    // Fallback: Generate words if missing to ensure karaoke effect works
    if (words.isEmpty && line.line.text.isNotEmpty) {
      final start = line.line.start;
      final end = line.line.end;
      
      var effectiveEnd = end;
      if (effectiveEnd == null || effectiveEnd <= start) {
        final model = controller.lyricNotifier.value;
        if (model != null && index + 1 < model.lines.length) {
          final nextStart = model.lines[index + 1].start;
          if (nextStart > start) {
            effectiveEnd = nextStart;
          }
        }
        effectiveEnd ??= start + const Duration(seconds: 3);
      }
      final generated = LyricsParser.generateWords(line.line.text, start, effectiveEnd);
      if (generated != null) {
        words = generated;
      }
    }

    // Measure words if needed
    if (_currentWordWidths == null && words.isNotEmpty) {
      final style = line.activeTextPainter.text?.style;
      if (style != null) {
        _currentWordWidths =
            words.map((w) => _measureText(w.text, style)).toList();
      }
    }

    // Use cached widths or 0 if something failed
    final wordWidths = _currentWordWidths ?? List.filled(words.length, 0.0);

    var newWidth = 0.0;
    final currentProgress = controller.progressNotifier.value +
        Duration(milliseconds: controller.lyricOffset);

    final totalWidth = wordWidths.fold(0.0, (sum, w) => sum + w);
    final activeTextWidth = line.activeTextPainter.width;
    final widthScale = totalWidth > 0 && activeTextWidth > totalWidth
        ? activeTextWidth / totalWidth
        : 1.0;
    final model = controller.lyricNotifier.value;
    Duration? lineEnd = line.line.end;
    if (lineEnd == null && model != null && index + 1 < model.lines.length) {
      lineEnd = model.lines[index + 1].start;
    }
    if (lineEnd != null && currentProgress >= lineEnd) {
      _animationController.stop();
      activeHighlightWidthNotifier.value = activeTextWidth;
      return;
    }
    const defaultWordDurationMs = 120;
    for (var i = 0; i < words.length; i++) {
      final wordMetric = words[i];
      final wordWidth = wordWidths[i];
      final wordStart = wordMetric.start;
      if (currentProgress < wordStart) {
        break;
      }
      newWidth += wordWidth;
      final rawEnd = wordMetric.end;
      final hasValidEnd = rawEnd != null && rawEnd > wordStart;
      var wordEnd = hasValidEnd
          ? rawEnd
          : wordStart + const Duration(milliseconds: defaultWordDurationMs);
      if (i + 1 < words.length) {
        final nextStart = words[i + 1].start;
        if (rawEnd == null && nextStart > wordStart) {
          wordEnd = nextStart;
        }
      } else if (!hasValidEnd && lineEnd != null && lineEnd > wordStart) {
        wordEnd = lineEnd;
      }
      if (currentProgress < wordEnd) {
        final wordDuration = (wordEnd - wordStart).inMilliseconds;
        final elapsed = (currentProgress - wordStart).inMilliseconds;
        if (wordDuration > 0) {
          newWidth -= wordWidth * (1 - elapsed / wordDuration);
        }
      }
    }
    if (words.isNotEmpty) {
      _animationController.stop();
      activeHighlightWidthNotifier.value = newWidth * widthScale;
      return;
    }
    
    // Fallback to full highlight if no words available
    activeHighlightWidthNotifier.value = double.infinity;
  }

  void _animateWidth(double newWidth) {
    final currentWidth = activeHighlightWidthNotifier.value;
    if (currentWidth == newWidth) return;
    if (newWidth < currentWidth) {
      _animationController.stop();
      activeHighlightWidthNotifier.value = newWidth;
      return;
    }
    _widthAnimation = Tween<double>(
      begin: currentWidth,
      end: newWidth,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ),
    );
    _animationController
      ..reset()
      ..forward();
  }

  Widget buildActiveHighlightWidth(Widget Function(double value) builder) {
    return ValueListenableBuilder<double>(
      valueListenable: activeHighlightWidthNotifier,
      builder: (context, value, child) {
        return builder(value);
      },
    );
  }
}
