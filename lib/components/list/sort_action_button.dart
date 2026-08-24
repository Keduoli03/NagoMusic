import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'media_list_action_button.dart';

class SortActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const SortActionButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MediaListActionButton(
      icon: AppIcons.sort,
      tooltip: '排序',
      onTap: onTap,
    );
  }
}
