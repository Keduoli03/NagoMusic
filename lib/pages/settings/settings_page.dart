import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../../components/index.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppSettingSection(
            title: '播放体验',
            children: [
              AppSettingTile(
                title: '流光设置',
                subtitle: '封面流光与渐变参数',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.gradientSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '功能',
            children: [
              AppSettingTile(
                title: '歌词设置',
                subtitle: '状态栏歌词与显示偏好',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.lyricsSettings,
                ),
              ),
              AppSettingTile(
                title: '缓存设置',
                subtitle: '管理音频缓存与存储空间',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.cacheSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '应用',
            children: [
              AppSettingTile(
                title: '版本信息',
                subtitle: 'NagoMusic',
                trailing: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
