import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../viewmodels/library_viewmodel.dart';
import 'app_list_tile.dart';

class BlockedFoldersSheet extends StatefulWidget {
  final String sourceId;
  final List<FolderInfo> allFolders;

  const BlockedFoldersSheet({
    super.key,
    required this.sourceId,
    required this.allFolders,
  });

  @override
  State<BlockedFoldersSheet> createState() => _BlockedFoldersSheetState();
}

class _BlockedFoldersSheetState extends State<BlockedFoldersSheet> {
  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);
      watchSignal(context, vm.scanTick);
      
      final source = vm.sources.firstWhere(
        (s) => s.id == widget.sourceId,
        orElse: () => vm.getOrCreateLocalSource(),
      );
      
      final exclude = source.excludeFolders;

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final background = isDark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1C1F24),
                Color(0xFF22262C),
                Color(0xFF1B1D22),
              ],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF6F7FB),
                Color(0xFFF7F3E8),
                Color(0xFFF1F7F4),
              ],
            );

      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          gradient: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 32,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24, bottom: 8),
                child: Text(
                  '被屏蔽的文件夹',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (exclude.isEmpty)
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('暂无屏蔽的文件夹'),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: exclude.length,
                    itemBuilder: (context, index) {
                      final id = exclude[index];
                      String name = '未知文件夹';
                      try {
                        final match = widget.allFolders.firstWhere((f) => f.id == id);
                        name = match.name;
                      } catch (_) {
                        if (id.contains('/') || id.contains('\\')) {
                          if (id.contains('/')) {
                             name = id.split('/').last;
                          } else {
                             name = id.split('\\').last;
                          }
                          if (name.isEmpty) name = id;
                        } else {
                          name = id;
                        }
                      }

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: AppListTile(
                          leading: const Icon(Icons.folder_off, color: Colors.grey),
                          title: name,
                          subtitle: id,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final newExclude = List<String>.from(exclude)..remove(id);
                              final updated = source.copyWith(excludeFolders: newExclude);
                              await vm.upsertSource(updated);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },);
  }
}
