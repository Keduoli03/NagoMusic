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
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Widget _modeTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = selected
        ? scheme.primary
        : (isDark ? Colors.white12 : Colors.black12);
    final iconColor =
        selected ? scheme.primary : (isDark ? Colors.white70 : Colors.black54);
    final textColor =
        selected ? scheme.primary : (isDark ? Colors.white70 : Colors.black87);
    final background =
        selected ? scheme.primary.withAlpha(31) : Colors.transparent;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRow(
    BuildContext context, {
    required ThemeMode selected,
    required ValueChanged<ThemeMode> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          _modeTile(
            context,
            icon: Icons.phone_android,
            label: _themeLabel(ThemeMode.system),
            selected: selected == ThemeMode.system,
            onTap: () => onChanged(ThemeMode.system),
          ),
          const SizedBox(width: 8),
          _modeTile(
            context,
            icon: Icons.light_mode_outlined,
            label: _themeLabel(ThemeMode.light),
            selected: selected == ThemeMode.light,
            onTap: () => onChanged(ThemeMode.light),
          ),
          const SizedBox(width: 8),
          _modeTile(
            context,
            icon: Icons.dark_mode_outlined,
            label: _themeLabel(ThemeMode.dark),
            selected: selected == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
          ),
        ],
      ),
    );
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
            title: '播放体验',
            children: [
              ValueListenableBuilder<bool>(
                valueListenable:
                    PlayerBackgroundSettings.dynamicGradientEnabled,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '动态流光',
                    subtitle: '背景随封面颜色流动变化',
                    value: enabled,
                    onChanged: (value) {
                      PlayerBackgroundSettings.setDynamicGradientEnabled(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable:
                    PlayerBackgroundSettings.dynamicGradientEnabled,
                builder: (context, enabled, _) {
                  if (!enabled) {
                    return const SizedBox.shrink();
                  }
                  return AppSettingTile(
                    title: '流光设置',
                    subtitle: '封面流光与渐变参数',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.gradientSettings,
                    ),
                  );
                },
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable:
                    PlayerBackgroundSettings.playbackThemeMode,
                builder: (context, mode, _) {
                  return _modeRow(
                    context,
                    selected: mode,
                    onChanged: (value) {
                      PlayerBackgroundSettings.setPlaybackThemeMode(value);
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '外观',
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AppLayoutSettings.tabletMode,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '平板模式',
                    subtitle: '优化平板布局',
                    value: enabled,
                    onChanged: (value) {
                      AppLayoutSettings.setTabletMode(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeSettings.themeMode,
                builder: (context, mode, _) {
                  return _modeRow(
                    context,
                    selected: mode,
                    onChanged: (value) {
                      AppThemeSettings.setThemeMode(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppThemeSettings.dynamicColorEnabled,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '使用系统动态颜色',
                    subtitle: '仅 Android 12+ 生效',
                    value: enabled,
                    onChanged: (value) {
                      AppThemeSettings.setDynamicColorEnabled(value);
                    },
                  );
                },
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
