import 'package:flutter/material.dart';

class SourceTileAction {
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;
  final String? tooltip;

  const SourceTileAction({
    required this.icon,
    required this.onTap,
    this.isLoading = false,
    this.tooltip,
  });
}

class SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<SourceTileAction> actions;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const SourceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...actions.map(
            (action) => IconButton(
              icon: action.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(action.icon),
              tooltip: action.tooltip,
              onPressed: action.onTap,
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
