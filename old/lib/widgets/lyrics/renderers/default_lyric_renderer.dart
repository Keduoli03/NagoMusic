import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as lyric_model;
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';
import '../animations/lyric_animation_strategy.dart';
import 'lyric_renderer.dart';

class DefaultLyricRenderer implements LyricRenderer {
  const DefaultLyricRenderer();

  @override
  void paintLine({
    required Canvas canvas,
    required lyric_model.LineMetrics metric,
    required Size size,
    required int index,
    required bool isActive,
    required bool isInAnchorArea,
    required bool isSelecting,
    required bool showSelectionShadow,
    required bool showTranslationText,
    required LyricLayout layout,
    required LyricStyle style,
    required LyricAnimationStrategy animationStrategy,
    required LyricLineSwitchState switchState,
    required double activeHighlightWidth,
    bool isKaraoke = false,
  }) {
    final mainHeight = isActive ? metric.activeHeight : metric.height;
    
    // Draw selection shadow
    if (showSelectionShadow && isInAnchorArea) {
      var blockHeight = mainHeight;
      if (metric.line.translation?.isNotEmpty == true) {
        blockHeight +=
            layout.style.translationLineGap + metric.translationTextPainter.height;
      }
      const verticalPadding = 4.0;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          -verticalPadding,
          size.width,
          blockHeight + verticalPadding * 2,
        ),
        const Radius.circular(6),
      );
      final paint = Paint()
        ..color = layout.style.selectedColor.withValues(alpha: 0.12);
      canvas.drawRRect(rect, paint);
    }

    TextStyle replaceTextStyle(TextStyle style, Color color) {
      return style.copyWith(
        color: isSelecting && isInAnchorArea ? color : style.color,
      );
    }

    final painter = isActive ? metric.activeTextPainter : metric.textPainter;
    final hasTranslation = metric.line.translation?.isNotEmpty == true;
    final contentWidth = hasTranslation
        ? math.max(painter.width, metric.translationTextPainter.width)
        : painter.width;

    double calcInnerAlignOffset(double lineWidth) {
      switch (layout.style.lineTextAlign) {
        case TextAlign.left:
        case TextAlign.start:
        case TextAlign.justify:
          return 0;
        case TextAlign.right:
        case TextAlign.end:
          return contentWidth - lineWidth;
        case TextAlign.center:
          return (contentWidth - lineWidth) / 2;
      }
    }

    final baseOffset = _calcContentAliginOffset(contentWidth, size.width, layout);
    final oldSpan = painter.text!;
    final availableWidth = size.width - layout.style.contentPadding.horizontal;
    if (isSelecting && isInAnchorArea) {
      painter.text = TextSpan(
        text: oldSpan.toPlainText(),
        style: replaceTextStyle(
          oldSpan.style!,
          layout.style.selectedColor,
        ),
      );
      painter.layout(maxWidth: availableWidth);
    }
    
    canvas.save();
    canvas.translate(baseOffset, 0);
    
    // Apply animation
    final switchOffset = animationStrategy.apply(
      canvas: canvas,
      metric: metric,
      index: index,
      switchState: switchState,
      contentWidth: contentWidth,
      size: size,
      layout: layout,
    );
    
    final shouldHighlight = isActive ||
        (index == switchState.exitIndex &&
            switchState.exitAnimationValue < 1 &&
            style.enableSwitchAnimation);

    canvas.save();
    canvas.translate(calcInnerAlignOffset(painter.width), 0);
    
    if (shouldHighlight) {
      final hasHighlight = layout.style.activeHighlightColor != null ||
          layout.style.activeHighlightGradient != null;

      // Always draw the base text first.
      // For karaoke: This provides the "inactive" color background.
      // For normal: This draws the text (redundant if no highlight, but consistent).
      painter.paint(canvas, const Offset(0, 0));

      if (hasHighlight) {
        final mainHeight = isActive ? metric.activeHeight : metric.height;
        canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, mainHeight), Paint());
        // Draw text again to serve as the mask for the highlight
        painter.paint(canvas, const Offset(0, 0));
        _drawHighlight(
          canvas: canvas,
          layout: layout,
          style: style,
          metrics: isActive ? metric.activeMetrics : metric.metrics,
          highlightTotalWidth: isActive && (isKaraoke || metric.line.words?.isNotEmpty == true)
              ? activeHighlightWidth
              : double.infinity,
        );
        canvas.restore();
      }
    } else {
      painter.paint(
        canvas,
        const Offset(0, 0),
      );
    }
    canvas.restore();

    if (isSelecting && isInAnchorArea) {
      painter.text = oldSpan;
      painter.layout(maxWidth: size.width);
    }

    if (hasTranslation && showTranslationText) {
      final tPainter = metric.translationTextPainter;
      final tOldSpan = tPainter.text;
      
      // Calculate active translation font size based on main text scale ratio
      final activeScaleRatio = layout.style.activeStyle.fontSize! / layout.style.textStyle.fontSize!;
      
      final activeFontSize = isActive 
          ? layout.style.translationStyle.fontSize! * activeScaleRatio 
          : layout.style.translationStyle.fontSize;

      tPainter.text = TextSpan(
        text: metric.line.translation,
        style: replaceTextStyle(
          tPainter.text!.style!.copyWith(
            color: isActive ? layout.style.translationActiveColor : null,
            fontWeight: isActive ? FontWeight.bold : null,
            fontSize: activeFontSize,
          ),
          layout.style.selectedTranslationColor,
        ),
      );
      
      // Ensure alignment matches preference
      final originalTextAlign = tPainter.textAlign;
      tPainter.textAlign = layout.style.lineTextAlign;
      
      tPainter.layout(maxWidth: size.width);
      canvas.save();
      canvas.translate(calcInnerAlignOffset(tPainter.width), 0);
      canvas.translate(0, switchOffset);
      
      tPainter.paint(
        canvas,
        Offset(0, mainHeight + layout.style.translationLineGap),
      );
      tPainter.text = tOldSpan;
      tPainter.textAlign = originalTextAlign;
      tPainter.layout(maxWidth: size.width);
      canvas.restore();
    }
    canvas.restore();
  }

  double _calcContentAliginOffset(double contentWidth, double containerWidth, LyricLayout layout) {
    switch (layout.style.lineTextAlign) {
      case TextAlign.left:
      case TextAlign.start:
      case TextAlign.justify:
        return 0;
      case TextAlign.right:
      case TextAlign.end:
        return containerWidth - contentWidth;
      case TextAlign.center:
        return (containerWidth - contentWidth) / 2;
    }
  }

  void _drawHighlight({
    required Canvas canvas,
    required LyricLayout layout,
    required LyricStyle style,
    required List<ui.LineMetrics> metrics,
    double highlightTotalWidth = 0,
  }) {
    if (highlightTotalWidth < 0) return;
    final activeHighlightColor = layout.style.activeHighlightColor;
    final activeHighlightGradient = layout.style.activeHighlightGradient;
    if (activeHighlightColor == null && activeHighlightGradient == null) {
      return;
    }
    final highlightFullMode = highlightTotalWidth == double.infinity;
    var accWidth = 0.0;
    final Paint paint = Paint()..blendMode = BlendMode.srcIn;
    for (var line in metrics) {
      double lineDrawWidth;
      bool isFullLine;
      if (highlightFullMode) {
        isFullLine = true;
        lineDrawWidth = line.width;
      } else {
        final remain = highlightTotalWidth - accWidth;
        if (remain <= 0) break;
        lineDrawWidth = remain < line.width ? remain : line.width;
        isFullLine = remain >= line.width;
      }
      final top = line.baseline - line.ascent;
      final height = (line.ascent + line.descent);
      final extraFadeWidth = style.activeHighlightExtraFadeWidth;
      final pad = 2;
      final rect = Rect.fromLTWH(
        line.left - pad,
        top,
        lineDrawWidth + pad,
        height,
      );
      final grad = style.activeHighlightGradient ??
          LinearGradient(colors: [activeHighlightColor!, activeHighlightColor]);
      if (extraFadeWidth > 0) {
        paint.shader = LinearGradient(
          colors: [
            grad.colors.last,
            style.activeStyle.color ?? grad.colors.last,
          ],
        ).createShader(
          Rect.fromLTWH(
            rect.left + rect.width,
            rect.top,
            extraFadeWidth,
            rect.height,
          ),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + rect.width,
            rect.top,
            extraFadeWidth,
            rect.height,
          ),
          paint,
        );
      }
      paint.shader = grad.createShader(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height),
      );
      canvas.drawRect(rect, paint);
      accWidth += line.width;
      if (!isFullLine) break;
    }
  }
}
