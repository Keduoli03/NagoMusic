import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as lyric_model;
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/render/lyric_layout.dart';
import 'package:flutter_lyric/widgets/mixins/lyric_line_switch_mixin.dart';
import '../animations/lyric_animation_strategy.dart';

/// Strategy interface for rendering lyric lines.
abstract class LyricRenderer {
  /// Paints a single lyric line.
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
  });
}
