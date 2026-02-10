import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../viewmodels/library_viewmodel.dart';
import '../widgets/app_background.dart';
import 'albums/albums_page.dart';
import 'artists/artists_page.dart';
import 'playlists_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget _entryCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark
        ? const Color.fromARGB(28, 0, 0, 0)
        : const Color.fromARGB(15, 0, 0, 0);
    final iconColor =
        isDark ? Colors.white70 : const Color.fromARGB(255, 40, 40, 40);
    final textColor =
        isDark ? Colors.white : const Color.fromARGB(255, 45, 45, 45);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.settingsTick);

      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () {
              final val = LibraryViewModel().isMenuOpen.value;
              LibraryViewModel().isMenuOpen.value = !val;
            },
          ),
          title: const Text('首页'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            PopupMenuButton<SongFilter>(
              icon: const Icon(Icons.filter_list),
              initialValue: vm.homeFilter,
              tooltip: '筛选',
              onSelected: (filter) {
                vm.setHomeFilter(filter);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: SongFilter.all,
                  child: Text('全部'),
                ),
                const PopupMenuItem(
                  value: SongFilter.local,
                  child: Text('本地音乐'),
                ),
                const PopupMenuItem(
                  value: SongFilter.webdav,
                  child: Text('WebDAV'),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AppBackground(
          child: SafeArea(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音乐库',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final itemWidth = (width - 16) / 2;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: itemWidth,
                            child: _entryCard(
                              context,
                              icon: Icons.person,
                              label: '艺术家',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ArtistsPage(),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: itemWidth,
                            child: _entryCard(
                              context,
                              icon: Icons.album,
                              label: '专辑',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AlbumsPage(),
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: itemWidth,
                            child: _entryCard(
                              context,
                              icon: Icons.queue_music,
                              label: '歌单',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PlaylistsPage(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },);
  }
}
