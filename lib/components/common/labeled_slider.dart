import 'package:flutter/material.dart';

class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.label,
    this.tickCount,
    this.valueText,
    this.description,
    this.titleWidth = 90,
    this.titleFontSize = 15,
    this.padding,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final int? tickCount;
  final String? valueText;
  final String? description;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double titleWidth;
  final double titleFontSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tickColor = colors.primary;
    final tickInactiveColor = colors.onSurfaceVariant.withValues(alpha: 0.6);
    final theme = SliderTheme.of(context).copyWith(
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
      activeTickMarkColor: tickColor,
      inactiveTickMarkColor: tickInactiveColor,
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.onSurfaceVariant.withValues(alpha: 0.24),
      overlayColor: colors.primary.withValues(alpha: 0.12),
      showValueIndicator: divisions == null
          ? ShowValueIndicator.never
          : ShowValueIndicator.onlyForDiscrete,
    );
    final displayValue = (valueText ?? '').trim().isEmpty ? null : valueText;
    final detail = (description ?? '').trim().isEmpty ? null : description;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: titleWidth,
                child: Text(
                  title,
                  style: TextStyle(fontSize: titleFontSize),
                ),
              ),
              const Spacer(),
              if (displayValue != null)
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: theme,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: label,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
