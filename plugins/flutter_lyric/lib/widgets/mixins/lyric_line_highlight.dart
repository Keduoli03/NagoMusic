import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';

const Duration _kHighlightTransitionDuration = Duration(milliseconds: 200);

// 必须混入 TickerProviderStateMixin 才能使用 AnimationController
mixin LyricLineHightlightMixin<T extends StatefulWidget>
    on State<T>, LyricLayoutMixin<T>, TickerProviderStateMixin<T> {
  late final AnimationController _animationController;
  Animation<double>? _widthAnimation;

  var activeHighlightWidthNotifier = ValueNotifier(0.0);
  int? _lastActiveIndex;
  List<double>? _currentWordWidths;
  Duration _lastProgress = Duration.zero;
  int _lastUpdateAtMs = 0;
  bool _justSwitchedLine = false;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: _kHighlightTransitionDuration,
    );

    // 监听动画值的变化，并将最新值通知给 ValueNotifier
    _animationController.addListener(() {
      if (_widthAnimation != null) {
        activeHighlightWidthNotifier.value = _widthAnimation!.value;
      }
    });

    controller.activeIndexNotifiter.addListener(_onActiveIndexChange);
    controller.progressNotifier.addListener(updateHighlightWidth);

    super.initState();
  }

  _onActiveIndexChange() {
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

  List<LyricWord>? _generateFallbackWords(
    String text,
    Duration start,
    Duration end,
  ) {
    final runes = text.runes.toList();
    final len = runes.length;
    if (len <= 0) return null;
    if (len > 5000) return null;
    final totalMs = end.inMilliseconds - start.inMilliseconds;
    if (totalMs <= 0) return null;
    final words = <LyricWord>[];
    for (int i = 0; i < len; i++) {
      final ch = String.fromCharCode(runes[i]);
      final wordStartMs = start.inMilliseconds + ((totalMs * i) ~/ len);
      final wordEndMs = i == len - 1
          ? end.inMilliseconds
          : start.inMilliseconds + ((totalMs * (i + 1)) ~/ len);
      final ws = Duration(milliseconds: wordStartMs);
      final we = Duration(milliseconds: (wordEndMs <= wordStartMs)
          ? (wordStartMs + 1)
          : wordEndMs);
      words.add(LyricWord(text: ch, start: ws, end: we));
    }
    return words;
  }

  void updateHighlightWidth() {
    final index = controller.activeIndexNotifiter.value;
    final metrics = layout?.metrics ?? [];

    if (index >= metrics.length || index < 0) {
      _animateWidth(0.0);
      return;
    }

    final line = metrics[index];
    final currentProgress = controller.progressNotifier.value +
        Duration(milliseconds: controller.lyricOffset);

    if (_lastActiveIndex != index) {
      _lastActiveIndex = index;
      _currentWordWidths = null;
      _lastProgress = currentProgress;
      _lastUpdateAtMs = 0;
      _justSwitchedLine = true;
      _animationController.stop();
      activeHighlightWidthNotifier.value = 0.0;
    }

    var words = line.line.words ?? const <LyricWord>[];
    if (words.isEmpty && line.line.text.isNotEmpty) {
      final start = line.line.start;
      var end = line.line.end;
      if (end == null || end <= start) {
        final model = controller.lyricNotifier.value;
        if (model != null && index + 1 < model.lines.length) {
          final nextStart = model.lines[index + 1].start;
          if (nextStart > start) {
            end = nextStart;
          }
        }
        end ??= start + const Duration(seconds: 3);
      }
      final generated = _generateFallbackWords(line.line.text, start, end);
      if (generated != null && generated.isNotEmpty) {
        words = generated;
      }
    }

    final style = line.activeTextPainter.text?.style;
    if (_currentWordWidths == null && style != null && words.isNotEmpty) {
      _currentWordWidths = words.map((w) => _measureText(w.text, style)).toList();
    }
    final wordWidths = _currentWordWidths ?? List.filled(words.length, 0.0);

    final activeTextWidth = line.activeTextPainter.width;
    final totalWidth = wordWidths.fold<double>(0.0, (sum, w) => sum + w);
    final widthScale =
        totalWidth > 0 && activeTextWidth > totalWidth ? activeTextWidth / totalWidth : 1.0;

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

    if (words.isEmpty) {
      _animateWidth(0.0);
      _lastProgress = currentProgress;
      return;
    }

    if (activeTextWidth <= 0 || totalWidth <= 0) {
      final lineStart = line.line.start;
      final end = lineEnd;
      if (end != null && end > lineStart) {
        final totalMs = (end - lineStart).inMilliseconds;
        final elapsedMs = (currentProgress - lineStart).inMilliseconds;
        final ratio = (elapsedMs / totalMs).clamp(0.0, 1.0);
        _animateWidth(activeTextWidth * ratio);
        _lastProgress = currentProgress;
        return;
      }
    }

    var newWidth = 0.0;
    const defaultWordDurationMs = 120;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final wordWidth = wordWidths[i];
      final wordStart = word.start;
      if (currentProgress < wordStart) break;
      newWidth += wordWidth;

      final rawEnd = word.end;
      final hasValidEnd = rawEnd != null && rawEnd > wordStart;
      Duration wordEnd = hasValidEnd
          ? rawEnd!
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

    var scaledWidth = (newWidth * widthScale).clamp(0.0, activeTextWidth);
    final currentWidth = activeHighlightWidthNotifier.value;
    if (!_justSwitchedLine &&
        currentProgress >= _lastProgress &&
        scaledWidth < currentWidth) {
      scaledWidth = currentWidth;
    }
    _animateWidth(scaledWidth);
    _lastProgress = currentProgress;
    _justSwitchedLine = false;
  }

  void _animateWidth(double newWidth) {
    final currentWidth = activeHighlightWidthNotifier.value;

    // 1. 如果新宽度与当前宽度相同，不做任何事。
    if (currentWidth == newWidth) return;
    if (newWidth < currentWidth) {
      _animationController.stop();
      activeHighlightWidthNotifier.value = newWidth;
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastUpdateAtMs > 0) {
      final dt = (nowMs - _lastUpdateAtMs).clamp(60, 280);
      _animationController.duration = Duration(milliseconds: dt);
    } else {
      _animationController.duration = _kHighlightTransitionDuration;
    }
    _lastUpdateAtMs = nowMs;
    // 线性动画，无论增减都线性过渡
    _widthAnimation = Tween<double>(
      begin: currentWidth,
      end: newWidth,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));

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
