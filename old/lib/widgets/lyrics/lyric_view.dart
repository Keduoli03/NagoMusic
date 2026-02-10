import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/core/lyric_styles.dart';
import 'package:flutter_lyric/render/lyric_layout.dart' as lylayout;
import 'package:flutter_lyric/widgets/mixins/lyric_layout_mixin.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_mask_mixin.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_scroll_mixin.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_touch_mixin.dart';

import 'lyric_line_highlight_mixin.dart';
import 'lyric_painter.dart';

class LyricView extends StatefulWidget {
  final LyricController controller;
  final double? width;
  final double? height;
  final LyricStyle? style;
  final bool showTranslationText;

  const LyricView({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.style,
    this.showTranslationText = true,
  });

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView>
    with
        TickerProviderStateMixin,
        LyricLayoutMixin,
        LyricScrollMixin,
        LyricMaskMixin,
        LyricTouchMixin,
        LyricLineHighlightMixin,
        LyricLineSwitchMixin {
  final _selectionShadowNotifier = ValueNotifier(false);
  Timer? _selectionDwellTimer;

  @override
  LyricController get controller => widget.controller;

  @override
  LyricStyle get style => widget.style ?? LyricStyles.default1;

  @override
  lylayout.LyricLayout? layout;

  @override
  var lyricSize = Size.zero;

  @override
  final scrollYNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    controller.selectedIndexNotifier.addListener(_onSelectedIndexChange);
    controller.isSelectingNotifier.addListener(_onSelectingChange);
  }

  @override
  void dispose() {
    controller.selectedIndexNotifier.removeListener(_onSelectedIndexChange);
    controller.isSelectingNotifier.removeListener(_onSelectingChange);
    _selectionDwellTimer?.cancel();
    _selectionShadowNotifier.dispose();
    super.dispose();
  }

  void _onSelectingChange() {
    if (!controller.isSelectingNotifier.value) {
      _selectionDwellTimer?.cancel();
      _selectionShadowNotifier.value = false;
      return;
    }
    _startSelectionDwellTimer();
  }

  void _onSelectedIndexChange() {
    if (!controller.isSelectingNotifier.value) {
      return;
    }
    _startSelectionDwellTimer();
  }

  void _startSelectionDwellTimer() {
    _selectionDwellTimer?.cancel();
    _selectionShadowNotifier.value = false;
    updateScrollY(animate: false);
    _selectionDwellTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || !controller.isSelectingNotifier.value) {
        return;
      }
      _selectionShadowNotifier.value = true;
    });
  }

  @override
  void onStyleChange() {
    final oldStyle = layout?.style;
    super.onStyleChange();
    if (oldStyle == null) {
      return;
    }
    final newStyle = style;
    if (oldStyle.lineTextAlign != newStyle.lineTextAlign ||
        oldStyle.contentAlignment != newStyle.contentAlignment ||
        oldStyle.activeStyle.fontSize != newStyle.activeStyle.fontSize ||
        oldStyle.textStyle.fontSize != newStyle.textStyle.fontSize ||
        oldStyle.translationStyle.fontSize != newStyle.translationStyle.fontSize ||
        oldStyle.lineGap != newStyle.lineGap) {
      invalidateWordWidthCache();
      computeLyricLayout();
    }
  }

  @override
  void onLayoutChange(lylayout.LyricLayout layout) {
    super.onLayoutChange(layout);
    updateHighlightWidth();
    updateScrollY(animate: false);
  }

  @override
  void didUpdateWidget(covariant LyricView oldWidget) {
    // Explicitly check for critical style changes that affect layout, 
    // especially font size and scale changes which might be missed by object equality
    if (widget.style != oldWidget.style ||
        widget.style?.activeStyle.fontSize != oldWidget.style?.activeStyle.fontSize ||
        widget.style?.textStyle.fontSize != oldWidget.style?.textStyle.fontSize ||
        widget.style?.lineTextAlign != oldWidget.style?.lineTextAlign ||
        widget.style?.lineGap != oldWidget.style?.lineGap) {
      onStyleChange();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return wrapTouchWidget(
      context,
      SizedBox(
        width: widget.width ?? double.infinity,
        height: widget.height ?? double.infinity,
        child: Padding(
          padding: style.contentPadding.copyWith(top: 0, bottom: 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (size.width != lyricSize.width ||
                  size.height != lyricSize.height) {
                lyricSize = size;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  computeLyricLayout();
                });
              }
              if (layout == null) return const SizedBox.shrink();
              Widget result = buildLineSwitch((context, switchState) {
                return buildActiveHighlightWidth((double value) {
                  return ValueListenableBuilder(
                    valueListenable: scrollYNotifier,
                    builder: (context, double scrollY, child) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: _selectionShadowNotifier,
                        builder: (context, showSelectionShadow, child) {
                          return ValueListenableBuilder<int>(
                            valueListenable: controller.activeIndexNotifiter,
                            builder: (context, activeIndex, child) {
                              return CustomPaint(
                                painter: LyricPainter(
                                  layout: layout!,
                                  onShowLineRectsChange: (rects) {
                                    showLineRects = rects;
                                  },
                                  style: style,
                                  playIndex: activeIndex,
                                  activeHighlightWidth: value,
                                  isSelecting: controller.isSelectingNotifier.value,
                                  scrollY: scrollY,
                                  onAnchorIndexChange: (index) {
                                    scheduleMicrotask(() {
                                      controller.selectedIndexNotifier.value = index;
                                    });
                                  },
                                  switchState: switchState,
                                  showSelectionShadow: showSelectionShadow,
                                  showTranslationText: widget.showTranslationText,
                                ),
                                size: lyricSize,
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                });
              });
              result = wrapMaskIfNeed(result);
              return Stack(
                children: [
                  result,
                  _buildSelectionBar(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    if (layout == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isSelectingNotifier,
      builder: (context, selecting, child) {
        if (!selecting) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<int>(
          valueListenable: controller.selectedIndexNotifier,
          builder: (context, index, child) {
            final model = controller.lyricNotifier.value;
            final showDetails = selecting &&
                model != null &&
                index >= 0 &&
                index < model.lines.length;
            var timeText = '';
            if (showDetails) {
              timeText = _formatDuration(model.lines[index].start);
            }
            final selectionY = layout!.selectionAnchorPosition;
            final color = style.selectedColor;
            final translationColor = style.selectedTranslationColor;
            return Positioned(
              left: 0,
              right: 0,
              top: selectionY - 22,
              child: _LyricSelectionBar(
                timeText: timeText,
                color: color,
                secondaryColor: translationColor,
                showDetails: showDetails,
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration? value) {
    if (value == null) return '--:--';
    final m = value.inMinutes;
    final s = value.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _LyricSelectionBar extends StatelessWidget {
  final String timeText;
  final Color color;
  final Color secondaryColor;
  final bool showDetails;

  const _LyricSelectionBar({
    required this.timeText,
    required this.color,
    required this.secondaryColor,
    required this.showDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            if (showDetails)
              Text(
                timeText,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (showDetails) const SizedBox(width: 8),
            const Expanded(child: _LyricSolidLine()),
            if (showDetails) const SizedBox(width: 8),
            if (showDetails)
              Icon(
                Icons.play_arrow_rounded,
                size: 32,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

class _LyricSolidLine extends StatelessWidget {
  const _LyricSolidLine();

  @override
  Widget build(BuildContext context) {
    final lineColor = Colors.white.withValues(alpha: 0.4);
    return CustomPaint(
      painter: _LyricSolidLinePainter(lineColor),
      size: const Size(double.infinity, 1),
    );
  }
}

class _LyricSolidLinePainter extends CustomPainter {
  final Color color;

  _LyricSolidLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _LyricSolidLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
