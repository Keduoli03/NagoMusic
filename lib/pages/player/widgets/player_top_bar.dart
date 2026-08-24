import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

class PlayerTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onMore;

  const PlayerTopBar({super.key, required this.onBack, this.onMore});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(AppIcons.arrowLeft)),
          const Spacer(),
          IconButton(
            onPressed: onMore ?? () {},
            icon: Icon(AppIcons.moreHorizontal, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
