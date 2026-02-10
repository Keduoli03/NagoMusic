import 'package:flutter/material.dart';

class SortActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const SortActionButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.sort),
      onPressed: onTap,
    );
  }
}
