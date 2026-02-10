import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as lyric_model;
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';
import 'lyric_animation_strategy.dart';

/// Default implementation of [LyricAnimationStrategy] using scale and translate.
class ScaleTransitionStrategy implements LyricAnimationStrategy {
  const ScaleTransitionStrategy();

  @override
  double apply({
    required Canvas canvas,
    required lyric_model.LineMetrics metric,
    required int index,
    required LyricLineSwitchState switchState,
    required double contentWidth,
    required Size size,
    required LyricLayout layout,
  }) {
    if (layout.style.enableSwitchAnimation != true) return 0;
    if (metric.height <= 0 || metric.activeHeight <= 0) {
      return 0;
    }

    double calcTranslateX(double contentWidth) {
      switch (layout.style.lineTextAlign) {
        case TextAlign.right:
          return contentWidth;
        case TextAlign.center:
          return contentWidth / 2;
        case TextAlign.left:
        case TextAlign.start:
        case TextAlign.end:
        case TextAlign.justify:
          return 0;
      }
    }

    final transX = calcTranslateX(contentWidth);
    
    if (index == switchState.enterIndex) {
      final enterAnimationValue = switchState.enterAnimationValue;
      final fromHeight = metric.height;
      final toHeight = metric.activeHeight;
      
      // Safety check: avoid invalid dimensions
      if (fromHeight <= 1 || toHeight <= 1) return 0;

      final transY = toHeight;
      canvas.translate(transX, transY);
      
      // Use lerpDouble for safe and smooth interpolation
      // Start (0.0): scale = fromHeight / toHeight (looks like normal text)
      // End (1.0): scale = 1.0 (looks like active text)
      final targetStartScale = fromHeight / toHeight;
      var scale = ui.lerpDouble(targetStartScale, 1.0, enterAnimationValue) ?? 1.0;
      
      // Safety clamp: prevent scale from becoming too small (the "tiny font" bug)
      scale = scale.clamp(0.2, 5.0);
      
      canvas.scale(scale);
      canvas.translate(-transX, -transY);
    }
    
    if (index == switchState.exitIndex) {
      final exitAnimationValue = switchState.exitAnimationValue;
      final fromHeight = metric.activeHeight;
      final toHeight = metric.height;
      
      // Safety check
      if (fromHeight <= 1 || toHeight <= 1) return 0;

      final transY = 0.0;
      canvas.translate(transX, transY);
      
      // Start (0.0): scale = 1.0 (looks like active text)
      // End (1.0): scale = toHeight / fromHeight (looks like normal text)
      final targetStartScale = fromHeight / toHeight; // active / normal (> 1.0)
      var scale = ui.lerpDouble(targetStartScale, 1.0, exitAnimationValue) ?? 1.0;
      
      // Safety clamp
      scale = scale.clamp(0.2, 5.0);
      
      canvas.scale(scale);
      canvas.translate(-transX, -transY);
      
      return 0; 
    }
    
    return 0;
  }
}
