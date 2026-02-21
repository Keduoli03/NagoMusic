import 'package:flutter/material.dart';
import '../../app/router/app_router.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';
import '../player/widgets/player_background.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    PlayerBackgroundSettings.ensureLoaded();
    PlayerBottomActionSettings.ensureLoaded();
    WebDavPlaybackSettings.ensureLoaded();
    MediaNotificationSettings.ensureLoaded();
    AppLayoutSettings.ensureLoaded();
    AppBackgroundSettings.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '外观',
            children: [
              AppSettingTile(
                title: '应用外观',
                subtitle: '主题与背景设置',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.appAppearanceSettings,
                ),
              ),
              AppSettingTile(
                title: '播放器外观',
                subtitle: '流光与播放主题',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.playerAppearanceSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '功能',
            children: [
              AppSettingTile(
                title: '播放器控制',
                subtitle: '管理底部操作栏与按钮顺序',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.playerControlsSettings,
                ),
              ),
              AppSettingTile(
                title: '通知设置',
                subtitle: '媒体通知显示与按钮偏好',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.notificationSettings,
                ),
              ),
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
                title: '听歌统计',
                subtitle: '日历与播放数据概览',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.listeningStats,
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
            title: '云端播放',
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: WebDavPlaybackSettings.prefetchEnabled,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '预取下一首',
                    subtitle: '提前缓存下一首减少卡顿',
                    value: enabled,
                    onChanged: (value) {
                      WebDavPlaybackSettings.setPrefetchEnabled(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: WebDavPlaybackSettings.prefetchEnabled,
                builder: (context, enabled, _) {
                  if (!enabled) return const SizedBox.shrink();
                  return const SizedBox.shrink();
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '分段并发下载',
                    subtitle: '提高弱网下缓存速度',
                    value: enabled,
                    onChanged: (value) {
                      WebDavPlaybackSettings.setSegmentedEnabled(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                builder: (context, enabled, _) {
                  if (!enabled) return const SizedBox.shrink();
                  return ValueListenableBuilder<int>(
                    valueListenable:
                        WebDavPlaybackSettings.segmentConcurrency,
                    builder: (context, count, _) {
                      return AppSettingSlider(
                        title: '分段并发数',
                        description: '并发越高速度越快但更耗网络',
                        value: count.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        valueText: '$count',
                        onChanged: (value) {
                          WebDavPlaybackSettings.setSegmentConcurrency(
                            value.round(),
                          );
                        },
                      );
                    },
                  );
                },
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
