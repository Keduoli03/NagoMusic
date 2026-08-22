import 'package:flutter/material.dart';

import '../../app/theme/app_radii.dart';

/// 无封面时的占位图：圆角方块 + 首字母。
///
/// 各处封面尺寸、圆角、底色不同，通过参数区分；默认与列表行的样式一致。
class LetterArtworkPlaceholder extends StatelessWidget {
  /// 取首字母的来源文本（歌曲名 / 专辑名 / 艺术家名）。
  final String label;
  final double? size;
  final BorderRadius? borderRadius;

  /// 为 true 时底色用主题色淡色，否则用卡片色。
  final bool tintedBackground;
  final double? fontSize;
  final FontWeight fontWeight;
  final List<BoxShadow>? boxShadow;

  const LetterArtworkPlaceholder({
    super.key,
    required this.label,
    this.size,
    this.borderRadius,
    this.tintedBackground = false,
    this.fontSize,
    this.fontWeight = FontWeight.w600,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = label.trim();
    final letter = trimmed.isEmpty
        ? '?'
        : trimmed.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tintedBackground
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.cardColor,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.chip),
        boxShadow: boxShadow,
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: fontSize,
          color: theme.colorScheme.primary,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
