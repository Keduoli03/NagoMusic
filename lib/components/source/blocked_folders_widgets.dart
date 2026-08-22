import 'package:flutter/material.dart';

import '../../app/services/block_list_service.dart';
import '../common/blocked_management_sheet.dart';
import '../common/sheet_panels.dart';
import '../feedback/app_toast.dart';

/// 文件夹浏览页顶部的「已屏蔽的文件夹」入口卡片。
///
/// 点击后打开 [BlockedManagementSheet]，解除屏蔽后回调 [onChanged]。
class BlockedFoldersEntryCard extends StatelessWidget {
  /// [BlockListService] 中的屏蔽列表键（本地源与各 WebDAV 源互相独立）。
  final String blockListKey;
  final List<String> blocked;
  final VoidCallback onChanged;

  const BlockedFoldersEntryCard({
    super.key,
    required this.blockListKey,
    required this.blocked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 64,
        child: Material(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => BlockedManagementSheet(
                  title: '已屏蔽文件夹',
                  items: blocked.toList(),
                  onUnblock: (item) async {
                    await BlockListService.instance.remove(blockListKey, item);
                    if (context.mounted) {
                      Navigator.pop(context);
                      onChanged();
                    }
                  },
                ),
              );
            },
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.folder_off, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                const Expanded(child: Text('已屏蔽的文件夹')),
                Text('${blocked.length} 个'),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 长按文件夹时弹出的「屏蔽此文件夹」操作面板。
///
/// [pageContext] 用于在面板关闭后弹 toast，必须是仍然挂载的页面 context。
void showBlockFolderSheet(
  BuildContext pageContext, {
  required String blockListKey,
  required String folderId,
  required String folderName,
  required VoidCallback onBlocked,
}) {
  showModalBottomSheet(
    context: pageContext,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return AppSheetPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off, color: Colors.red),
              title: const Text('屏蔽此文件夹'),
              titleTextStyle: TextStyle(
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await BlockListService.instance.add(blockListKey, folderId);
                if (!pageContext.mounted) return;
                AppToast.show(pageContext, '已屏蔽: $folderName');
                onBlocked();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
