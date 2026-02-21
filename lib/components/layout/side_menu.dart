import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import 'base/app_page_scaffold.dart';

class SideMenu extends StatelessWidget {
  final ValueChanged<String>? onNavigate;
  final ValueChanged<String>? onPush;
  final VoidCallback? onCloseDrawer;

  const SideMenu({
    super.key,
    this.onNavigate,
    this.onPush,
    this.onCloseDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'NagoMusic',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                child: Column(
                  children: [
                    _buildMenuItem(
                      context,
                      Icons.music_note_rounded,
                      '歌曲',
                      () => _navigateAndClose(context, AppRoutes.songs),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.album_rounded,
                      '专辑',
                      () => _navigateAndClose(context, AppRoutes.albums),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.people_rounded,
                      '艺术家',
                      () => _navigateAndClose(context, AppRoutes.artists),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.queue_music_rounded,
                      '歌单',
                      () => _navigateAndClose(context, AppRoutes.playlists),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.library_music_rounded,
                      '音乐库',
                      () => _navigateAndClose(context, AppRoutes.home),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Divider(height: 1),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.radar_rounded,
                      '音源',
                      () => _navigateAndClose(context, AppRoutes.source),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.bar_chart_rounded,
                      '统计',
                      () => _pushAndClose(context, AppRoutes.listeningStats),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.settings_rounded,
                      '设置',
                      () => _pushAndClose(context, AppRoutes.settings),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
    );
  }

  void _navigateAndClose(BuildContext context, String route) {
    if (onNavigate != null) {
      onNavigate?.call(route);
      return;
    }
    if (!context.mounted) return;
    _closeDrawer(context);
    Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
  }

  void _pushAndClose(BuildContext context, String route) {
    if (onPush != null) {
      onPush?.call(route);
      return;
    }
    if (!context.mounted) return;
    _closeDrawer(context);
    Navigator.pushNamed(context, route);
  }

  void _closeDrawer(BuildContext context) {
    if (onCloseDrawer != null) {
      onCloseDrawer?.call();
      return;
    }
    if (!context.mounted) return;
    final state = context.findAncestorStateOfType<AppPageScaffoldState>();
    state?.closeDrawer();
  }
}
