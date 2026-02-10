import 'package:flutter/material.dart';

class LyricsActionsBar extends StatelessWidget {
  final bool hasTranslation;
  final bool showTranslation;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleTranslation;
  final Color color;

  const LyricsActionsBar({
    super.key,
    required this.hasTranslation,
    required this.showTranslation,
    required this.onOpenSettings,
    required this.onToggleTranslation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _LyricsBadge(
          text: '词',
          onTap: onOpenSettings,
          color: color,
        ),
        if (hasTranslation)
          _LyricsBadge(
            text: '译',
            isActive: showTranslation,
            onTap: onToggleTranslation,
            color: color,
            filled: true,
          ),
      ],
    );
  }
}

class _LyricsBadge extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isActive;
  final Color color;
  final bool filled;

  const _LyricsBadge({
    required this.text,
    required this.onTap,
    this.isActive = true,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = filled && isActive;
    final contentColor = isSelected
        ? (color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.transparent : contentColor,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: contentColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

