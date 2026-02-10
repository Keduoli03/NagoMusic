import 'package:flutter/material.dart';

class PlayerTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onMore;

  const PlayerTopBar({
    super.key,
    required this.onBack,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const Spacer(),
          IconButton(
            onPressed: onMore ?? () {},
            icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

