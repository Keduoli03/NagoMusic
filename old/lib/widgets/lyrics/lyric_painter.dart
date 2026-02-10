import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart' as lylayout;
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';
import 'animations/lyric_animation_strategy.dart';
import 'animations/scale_transition_strategy.dart';
import 'renderers/default_lyric_renderer.dart';
import 'renderers/lyric_renderer.dart';

class LyricPainter extends CustomPainter {
  final lylayout.LyricLayout layout;
  final int playIndex;
  final double scrollY;
  final double activeHighlightWidth;
  final LyricLineSwitchState switchState;
  final bool isSelecting;
  final LyricStyle style;
  final bool showSelectionShadow;
  final bool showTranslationText;
  final Function(int) onAnchorIndexChange;
  final Function(Map<int, Rect>) onShowLineRectsChange;
  final LyricAnimationStrategy animationStrategy;
  final LyricRenderer renderer;

  LyricPainter({
    required this.layout,
    required this.playIndex,
    required this.scrollY,
    required this.onAnchorIndexChange,
    required this.activeHighlightWidth,
    required this.switchState,
    required this.isSelecting,
    required this.onShowLineRectsChange,
    required this.style,
    required this.showSelectionShadow,
    required this.showTranslationText,
    this.animationStrategy = const ScaleTransitionStrategy(),
    this.renderer = const DefaultLyricRenderer(),
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(
      Rect.fromLTRB(
        -layout.style.contentPadding.left,
        0,
        size.width + layout.style.contentPadding.right,
        size.height,
      ),
    );
    final selectionPosition = layout.selectionAnchorPosition;
    var totalTranslateY = 0.0;
    canvas.translate(0, -scrollY);
    totalTranslateY -= scrollY;
    var selectedIndex = -1;
    final showLineRects = <int, Rect>{};
    
    // Pre-calculate scale ratio for translation text
    final activeScaleRatio = layout.style.activeStyle.fontSize! / layout.style.textStyle.fontSize!;

    for (var i = 0; i < layout.metrics.length; i++) {
      final isActive = i == playIndex;
      var lineHeight = layout.getLineHeight(isActive, i);
      
      // Calculate extra height for active translation if needed
      // We must manually calculate this because LyricLayout doesn't support active translation style
      if (isActive && showTranslationText && layout.metrics[i].line.translation?.isNotEmpty == true) {
        if (activeScaleRatio > 1.0) {
          final tPainter = layout.metrics[i].translationTextPainter;
          final originalHeight = tPainter.height;
          final tOldSpan = tPainter.text;
          final originalTextAlign = tPainter.textAlign;
          
          // Apply the active font size to translation painter to measure new height
          final activeTranslationFontSize = layout.style.translationStyle.fontSize! * activeScaleRatio;
          
          tPainter.text = TextSpan(
            text: layout.metrics[i].line.translation,
            style: tPainter.text!.style!.copyWith(
              fontSize: activeTranslationFontSize,
              fontWeight: FontWeight.bold,
            ),
          );
          
          // Ensure alignment matches preference (crucial for multi-line translation)
          tPainter.textAlign = layout.style.lineTextAlign;
          
          // Trigger layout to calculate height with wrapping
          tPainter.layout(maxWidth: size.width);
          final newHeight = tPainter.height;
          
          // Restore original state to avoid side effects on next paint
          tPainter.text = tOldSpan;
          tPainter.textAlign = originalTextAlign;
          tPainter.layout(maxWidth: size.width);
          
          // Restore height adjustment to fix overlap issue when translation wraps
          lineHeight += (newHeight - originalHeight);
        }
      }

      totalTranslateY += lineHeight;
      
      // Fix selection logic: Select the line whose vertical center is closest to selectionPosition
      // totalTranslateY is now the bottom of the content
      // Top of content is totalTranslateY - lineHeight
      // Center of content is totalTranslateY - lineHeight / 2
      
      // Let's stick to original logic but ensure lineHeight is accurate (fixed above).
      // Also, ensure we don't re-select if we already found one (selectedIndex == -1).
      if ((totalTranslateY + layout.style.lineGap / 2) >= selectionPosition &&
          selectedIndex == -1) {
        selectedIndex = i;
        onAnchorIndexChange(i);
      }
      if (totalTranslateY - lineHeight >= size.height) {
        break;
      }
      if (totalTranslateY > 0) {
        final lineRect = Rect.fromLTWH(
          0,
          totalTranslateY - lineHeight,
          size.width + layout.style.contentPadding.horizontal,
          lineHeight,
        );
        showLineRects[i] = lineRect;
        if (style.activeLineOnly && !isActive) {
        } else {
          renderer.paintLine(
            canvas: canvas,
            metric: layout.metrics[i],
            size: size,
            index: i,
            isActive: isActive,
            isInAnchorArea: selectedIndex == i,
            isSelecting: isSelecting,
            showSelectionShadow: showSelectionShadow,
            showTranslationText: showTranslationText,
            layout: layout,
            style: style,
            animationStrategy: animationStrategy,
            switchState: switchState,
            activeHighlightWidth: activeHighlightWidth,
            isKaraoke: activeHighlightWidth != double.infinity,
          );
        }
      }
      totalTranslateY += layout.style.lineGap;
      canvas.translate(0, lineHeight + layout.style.lineGap);
    }
    onShowLineRectsChange(showLineRects);
  }



  @override
  bool shouldRepaint(covariant LyricPainter oldDelegate) {
    final shouldRepaint = layout != oldDelegate.layout ||
        playIndex != oldDelegate.playIndex ||
        scrollY != oldDelegate.scrollY ||
        activeHighlightWidth != oldDelegate.activeHighlightWidth ||
        isSelecting != oldDelegate.isSelecting ||
        showSelectionShadow != oldDelegate.showSelectionShadow ||
        showTranslationText != oldDelegate.showTranslationText ||
        style != oldDelegate.style;
    return shouldRepaint;
  }
}
