import 'package:flutter/material.dart';

import 'media_list_action_button.dart';

class SortActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const SortActionButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MediaListActionButton(
      icon: Icons.sort_rounded,
      tooltip: '排序',
      onTap: onTap,
    );
  }
}
