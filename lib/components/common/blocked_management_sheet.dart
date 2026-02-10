import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../index.dart';

class BlockedManagementSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final ValueChanged<String> onUnblock;

  const BlockedManagementSheet({
    super.key,
    required this.title,
    required this.items,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      title: title,
      expand: true,
      child: items.isEmpty
          ? const Center(child: Text('暂无已屏蔽项'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                // For paths, we might want to show basename primarily, but keep full path visible
                // Or just show the string if it's not a path
                final name = p.basename(item);
                final isPath = name != item;
                
                return ListTile(
                  title: Text(isPath && name.isNotEmpty ? name : item),
                  subtitle: isPath ? Text(item, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.undo_rounded),
                    tooltip: '取消屏蔽',
                    onPressed: () => onUnblock(item),
                  ),
                );
              },
            ),
    );
  }
}
