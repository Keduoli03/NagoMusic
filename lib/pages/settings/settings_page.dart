import 'package:flutter/material.dart';
import '../../app/router/app_router.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    AppLayoutSettings.ensureLoaded();
    AppBackgroundSettings.ensureLoaded();
  }

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
            title: '设置',
            showBackButton: !useBottomNavigation,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
            children: const [
              AppSettingSection(
                title: '外观',
                children: [
                  AppSettingNavTile(
                    title: '应用外观',
                    subtitle: '主题、配色、导航布局与背景',
                    route: AppRoutes.appAppearanceSettings,
                  ),
                  AppSettingNavTile(
                    title: '播放器',
                    subtitle: '播放页样式、流光与底部操作栏',
                    route: AppRoutes.playerSettings,
                  ),
                ],
              ),
              SizedBox(height: 16),
              AppSettingSection(
                title: '功能',
                children: [
                  AppSettingNavTile(
                    title: '歌词',
                    subtitle: '状态栏歌词与显示偏好',
                    route: AppRoutes.lyricsSettings,
                  ),
                  AppSettingNavTile(
                    title: '通知与权限',
                    subtitle: '媒体通知按钮与系统权限',
                    route: AppRoutes.notificationSettings,
                  ),
                  AppSettingNavTile(
                    title: '存储与缓存',
                    subtitle: '缓存上限、下载目录与云端预取',
                    route: AppRoutes.cacheSettings,
                  ),
                ],
              ),
              SizedBox(height: 16),
              AppSettingSection(
                title: '应用',
                children: [
                  AppSettingNavTile(
                    title: '听歌统计',
                    subtitle: '日历与播放数据概览',
                    route: AppRoutes.listeningStats,
                  ),
                  AppSettingNavTile(
                    title: '数据备份',
                    subtitle: '歌单、听歌统计等导出到本地或 WebDAV',
                    route: AppRoutes.dataBackup,
                  ),
                  AppSettingNavTile(
                    title: '版本信息',
                    subtitle: '版本号、检查更新与调试日志',
                    route: AppRoutes.versionInfo,
                  ),
                ],
              ),
            ],
          ),
          bottomNavIndex: null,
          onBottomNavTap: null,
        );
      },
    );
  }
}
