import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as lyric_model;
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';

/// Strategy interface for lyric line switch animations.
abstract class LyricAnimationStrategy {
  /// Applies the animation transformation to the canvas.
  ///
  /// Returns a vertical offset compensation if needed (usually 0).
  double apply({
    required Canvas canvas,
    required lyric_model.LineMetrics metric,
    required int index,
    required LyricLineSwitchState switchState,
    required double contentWidth,
    required Size size,
    required LyricLayout layout,
  });
}
