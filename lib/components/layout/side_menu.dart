import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import '../../app/router/app_router.dart';
import 'base/app_page_scaffold.dart';

class SideMenu extends StatelessWidget {
  final ValueChanged<String>? onNavigate;
  final ValueChanged<String>? onPush;
  final VoidCallback? onCloseDrawer;

  const SideMenu({super.key, this.onNavigate, this.onPush, this.onCloseDrawer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Theme-tinted gradient instead of flat white, so the drawer reads as part
    // of the app's color scheme.
    final topColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.18 : 0.14),
      scheme.surfaceContainerHigh,
    );
    final bottomColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.08 : 0.05),
      scheme.surface,
    );
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.25);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, bottomColor],
          ),
          border: Border(right: BorderSide(color: borderColor)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    _sectionLabel(context, '资源库'),
                    _MenuItem(
                      icon: AppIcons.musicNote,
                      label: '歌曲',
                      onTap: () => _navigateAndClose(context, AppRoutes.songs),
                    ),
                    _MenuItem(
                      icon: AppIcons.album,
                      label: '专辑',
                      onTap: () => _navigateAndClose(context, AppRoutes.albums),
                    ),
                    _MenuItem(
                      icon: AppIcons.users,
                      label: '艺术家',
                      onTap: () =>
                          _navigateAndClose(context, AppRoutes.artists),
                    ),
                    _MenuItem(
                      icon: AppIcons.queue,
                      label: '歌单',
                      onTap: () =>
                          _navigateAndClose(context, AppRoutes.playlists),
                    ),
                    _MenuItem(
                      icon: AppIcons.folder,
                      label: '文件夹',
                      onTap: () =>
                          _navigateAndClose(context, AppRoutes.folders),
                    ),
                    _MenuItem(
                      icon: AppIcons.musicNotes,
                      label: '音乐库',
                      onTap: () => _navigateAndClose(context, AppRoutes.home),
                    ),
                    const SizedBox(height: 8),
                    _sectionLabel(context, '更多'),
                    _MenuItem(
                      icon: AppIcons.video,
                      label: 'B站',
                      onTap: () => _navigateAndClose(context, AppRoutes.bili),
                    ),
                    _MenuItem(
                      icon: AppIcons.radar,
                      label: '音源',
                      onTap: () => _navigateAndClose(context, AppRoutes.source),
                    ),
                    _MenuItem(
                      icon: AppIcons.chartBar,
                      label: '统计',
                      onTap: () =>
                          _pushAndClose(context, AppRoutes.listeningStats),
                    ),
                    _MenuItem(
                      icon: AppIcons.settings,
                      label: '设置',
                      onTap: () => _pushAndClose(context, AppRoutes.settings),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '返回音乐库',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _navigateAndClose(context, AppRoutes.home),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Image.asset('开发文档/NagoAPP图标.png', fit: BoxFit.cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NagoMusic',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '本地与云端音乐',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
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

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
