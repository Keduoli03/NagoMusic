import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import '../../app/router/app_router.dart';
import '../../app/services/playlists_service.dart';
import '../../components/index.dart';
import '../library/playlist_detail_page.dart';

/// 底部导航第 4 项「我的」入口页。
///
/// 侧栏模式下这些入口本来放在抽屉里；切到底部导航之后，为了不让「设置」独占底
/// 栏，把资源库 / 更多这些常用入口集中到这里，设置只作为其中一项。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) {
        final bottomPadding = AppPageScaffold.scrollableBottomPadding(
          context,
          hasBottomNav: useBottomNavigation,
        );
        return AppPageScaffold(
          extendBodyBehindAppBar: true,
          appBar: AppTopBar(
            title: '我的',
            showBackButton: !useBottomNavigation,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: '设置',
                icon: const Icon(AppIcons.settings),
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.settings),
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
            children: [
              AppSettingSection(
                title: '资源库',
                children: [
                  _tile(
                    context,
                    icon: AppIconsFilled.heart,
                    title: PlaylistsService.favoritePlaylistName,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const PlaylistDetailPage(
                          playlistId: PlaylistsService.favoritePlaylistId,
                        ),
                      ),
                    ),
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.queue,
                    title: '歌单',
                    route: AppRoutes.playlists,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.album,
                    title: '专辑',
                    route: AppRoutes.albums,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.users,
                    title: '艺术家',
                    route: AppRoutes.artists,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.folder,
                    title: '文件夹',
                    route: AppRoutes.folders,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSettingSection(
                title: '更多',
                children: [
                  _navTile(
                    context,
                    icon: AppIcons.radar,
                    title: '音源管理',
                    subtitle: '本地与云端音乐来源',
                    route: AppRoutes.source,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.chartBar,
                    title: '听歌统计',
                    subtitle: '日历与播放数据概览',
                    route: AppRoutes.listeningStats,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.hardDrive,
                    title: '数据备份',
                    subtitle: '歌单、听歌统计导出到本地或 WebDAV',
                    route: AppRoutes.dataBackup,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSettingSection(
                title: '应用',
                children: [
                  _navTile(
                    context,
                    icon: AppIcons.settings,
                    title: '设置',
                    subtitle: '外观、播放器、通知等',
                    route: AppRoutes.settings,
                  ),
                  _navTile(
                    context,
                    icon: AppIcons.info,
                    title: '版本信息',
                    subtitle: '版本号、检查更新与调试日志',
                    route: AppRoutes.versionInfo,
                  ),
                ],
              ),
            ],
          ),
          bottomNavIndex: useBottomNavigation ? 3 : null,
          onBottomNavTap: useBottomNavigation
              ? (index) => navigateToPrimaryDestination(context, index)
              : null,
        );
      },
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required String route,
  }) {
    return _tile(
      context,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => Navigator.pushNamed(context, route),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return AppSettingTile(
      title: title,
      subtitle: subtitle,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: scheme.primary),
      ),
      trailing: const Icon(AppIcons.chevronRight),
      onTap: onTap,
    );
  }
}
