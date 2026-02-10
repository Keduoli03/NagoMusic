import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../feedback/app_toast.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Material(
      color: isDark ? const Color(0xFF1C1F24) : const Color(0xFFF5F5F5),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
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
                      Icons.person,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NagoMusic',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '本地音乐库',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withAlpha(179),
                        ),
                      ),
                    ],
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
                      Icons.folder_rounded,
                      '文件夹',
                      () => _showPending(context),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.queue_music_rounded,
                      '歌单',
                      () => _navigateAndClose(context, AppRoutes.playlists),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Divider(height: 1),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.radar_rounded,
                      '扫描音乐',
                      () => _navigateAndClose(context, AppRoutes.source),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.library_music_rounded,
                      '音乐库',
                      () => _showPending(context),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.bar_chart_rounded,
                      '统计',
                      () => _showPending(context),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.settings_rounded,
                      '设置',
                      () => _pushAndClose(context, AppRoutes.settings),
                    ),
                    _buildMenuItem(
                      context,
                      Icons.info_outline_rounded,
                      '关于',
                      () => _showPending(context),
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
    Navigator.pop(context);
    Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
  }

  void _pushAndClose(BuildContext context, String route) {
    Navigator.pop(context);
    Navigator.pushNamed(context, route);
  }

  void _showPending(BuildContext context) {
    Navigator.pop(context);
    AppToast.show(context, '功能待接入');
  }
}
