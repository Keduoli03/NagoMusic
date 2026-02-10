import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../viewmodels/library_viewmodel.dart';
import 'app_list_tile.dart';

class BlockedArtistsSheet extends StatefulWidget {
  const BlockedArtistsSheet({super.key});

  @override
  State<BlockedArtistsSheet> createState() => _BlockedArtistsSheetState();
}

class _BlockedArtistsSheetState extends State<BlockedArtistsSheet> {
  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.settingsTick);
      final blocked = vm.blockedArtists;

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
                  '已屏蔽的艺术家',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (blocked.isEmpty)
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('暂无屏蔽的艺术家'),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: blocked.length,
                    itemBuilder: (context, index) {
                      final name = blocked[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: AppListTile(
                          leading: const Icon(Icons.person_off, color: Colors.grey),
                          title: name,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              vm.unblockArtist(name);
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

class BlockedAlbumsSheet extends StatefulWidget {
  const BlockedAlbumsSheet({super.key});

  @override
  State<BlockedAlbumsSheet> createState() => _BlockedAlbumsSheetState();
}

class _BlockedAlbumsSheetState extends State<BlockedAlbumsSheet> {
  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.settingsTick);
      final blocked = vm.blockedAlbums;

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
                  '已屏蔽的专辑',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (blocked.isEmpty)
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('暂无屏蔽的专辑'),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: blocked.length,
                    itemBuilder: (context, index) {
                      final name = blocked[index];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: AppListTile(
                          leading: const Icon(Icons.album_outlined, color: Colors.grey),
                          title: name,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              vm.unblockAlbum(name);
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
