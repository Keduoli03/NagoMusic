import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_surfaces.dart';
import '../common/glass_panel.dart';

class SourceSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SourceSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final titleColor = AppColors.of(context).text;
    final cardColor = theme.appPanelElevatedColor;
    final shadowColor = theme.appPanelShadowColor;
    final borderColor = theme.appPanelBorderColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        GlassPanel(
          borderRadius: BorderRadius.circular(22),
          color: cardColor,
          borderColor: borderColor,
          shadowColor: shadowColor,
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          child: Column(children: _withDividers(children)),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.isEmpty) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i != items.length - 1) {
        result.add(const SizedBox(height: 6));
      }
    }
    return result;
  }
}
