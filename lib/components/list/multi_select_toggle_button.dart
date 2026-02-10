import 'package:flutter/material.dart';

class MultiSelectToggleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const MultiSelectToggleButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(enabled ? Icons.checklist : Icons.checklist_rtl),
      onPressed: onTap,
    );
  }
}
