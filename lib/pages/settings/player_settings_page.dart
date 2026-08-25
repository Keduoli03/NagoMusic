import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../../app/state/settings_state.dart';
import '../../components/index.dart';
import '../../components/player/player_style_grid.dart';
import '../player/widgets/player_background.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  @override
  void initState() {
    super.initState();
    PlayerBackgroundSettings.ensureLoaded();
    PlayerStyleSettings.ensureLoaded();
    AppPlaybackVolumeSettings.ensureLoaded();
    PlayerBottomActionSettings.ensureLoaded();
    AppLaunchPlaybackSettings.ensureLoaded();
    MiniPlayerInfoSettings.ensureLoaded();
  }

  _BottomActionConfig _actionConfigByKey(String key) {
    switch (key) {
      case PlayerBottomActionSettings.playbackModeKey:
        return _BottomActionConfig(
          key: key,
          title: '随机/顺序按钮',
          subtitle: '控制播放模式切换',
          notifier: PlayerBottomActionSettings.showPlaybackMode,
          onChanged: PlayerBottomActionSettings.setShowPlaybackMode,
        );
      case PlayerBottomActionSettings.sleepTimerKey:
        return _BottomActionConfig(
          key: key,
          title: '定时按钮',
          subtitle: '显示睡眠定时入口',
          notifier: PlayerBottomActionSettings.showSleepTimer,
          onChanged: PlayerBottomActionSettings.setShowSleepTimer,
        );
      case PlayerBottomActionSettings.playlistKey:
        return _BottomActionConfig(
          key: key,
          title: '播放队列按钮',
          subtitle: '查看与调整播放队列',
          notifier: PlayerBottomActionSettings.showPlaylist,
          onChanged: PlayerBottomActionSettings.setShowPlaylist,
        );
      case PlayerBottomActionSettings.addToPlaylistKey:
        return _BottomActionConfig(
          key: key,
          title: '添加到歌单按钮',
          subtitle: '直接将当前歌曲加入歌单',
          notifier: PlayerBottomActionSettings.showAddToPlaylist,
          onChanged: PlayerBottomActionSettings.setShowAddToPlaylist,
        );
      case PlayerBottomActionSettings.saveToLocalKey:
        return _BottomActionConfig(
          key: key,
          title: '保存到本地按钮',
          subtitle: '直接保存当前歌曲文件',
          notifier: PlayerBottomActionSettings.showSaveToLocal,
          onChanged: PlayerBottomActionSettings.setShowSaveToLocal,
        );
      case PlayerBottomActionSettings.songInfoKey:
        return _BottomActionConfig(
          key: key,
          title: '歌曲信息按钮',
          subtitle: '查看文件、音质与标签信息',
          notifier: PlayerBottomActionSettings.showSongInfo,
          onChanged: PlayerBottomActionSettings.setShowSongInfo,
        );
      default:
        return _BottomActionConfig(
          key: PlayerBottomActionSettings.moreKey,
          title: '更多按钮',
          subtitle: '显示歌曲详情入口',
          notifier: PlayerBottomActionSettings.showMore,
          onChanged: PlayerBottomActionSettings.setShowMore,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '播放器',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '外观',
            children: [
              ValueListenableBuilder<PlayerStylePreset>(
                valueListenable: PlayerStyleSettings.stylePreset,
                builder: (context, selected, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text('播放器样式'),
                      ),
                      PlayerStyleGrid(
                        selected: selected,
                        onSelected: PlayerStyleSettings.setStylePreset,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      ),
                    ],
                  );
                },
              ),
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
                  return AppSettingNavTile(
                    title: '流光设置',
                    subtitle: '封面流光与渐变参数',
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.gradientSettings,
                    ),
                  );
                },
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: PlayerBackgroundSettings.playbackThemeMode,
                builder: (context, mode, _) {
                  return ThemeModeSelector(
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
            title: '播放行为',
            children: [
              ValueListenableBuilder<double>(
                valueListenable: AppPlaybackVolumeSettings.volume,
                builder: (context, volume, _) {
                  final percent = (volume * 100).round();
                  return AppSettingSlider(
                    title: '应用音量',
                    description: '只调整 NagoMusic 的播放音量，不改变系统音量',
                    value: volume,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    valueText: '$percent%',
                    onChanged: AppPlaybackVolumeSettings.setVolume,
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppLaunchPlaybackSettings.autoPlayOnAppLaunch,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '进入应用自动播放',
                    subtitle: '打开应用后自动开始播放当前歌曲',
                    value: enabled,
                    onChanged: (value) {
                      AppLaunchPlaybackSettings.setAutoPlayOnAppLaunch(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: MiniPlayerInfoSettings.showLyricsInSubtitle,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '播放器控件显示歌词',
                    subtitle: '开启后用当前歌词替代歌手名，长歌词会随播放自动滚动',
                    value: enabled,
                    onChanged: (value) {
                      MiniPlayerInfoSettings.setShowLyricsInSubtitle(value);
                    },
                  );
                },
              ),
            ],
          ),
          // 只有默认样式的控制区走可插拔按钮那一套；海报和沉浸都是固定的一排
          // 播放/暂停/上一首/下一首，没地方塞这些按钮，见 PlayerStyleCapabilities。
          ValueListenableBuilder<PlayerStylePreset>(
            valueListenable: PlayerStyleSettings.stylePreset,
            builder: (context, preset, _) {
              if (!preset.capabilities.customBottomActions) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  const SizedBox(height: 16),
                  AppSettingSection(
                    title: '底部操作栏',
                    children: [
                      ValueListenableBuilder<List<String>>(
                        valueListenable: PlayerBottomActionSettings.actionOrder,
                        builder: (context, order, _) {
                          return AppReorderableToggleList(
                            items: [
                              for (final key in order)
                                _actionConfigByKey(key).toToggleItem(),
                            ],
                            onReorder: (oldIndex, newIndex) {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final next = List<String>.from(order);
                              final item = next.removeAt(oldIndex);
                              next.insert(newIndex, item);
                              PlayerBottomActionSettings.setActionOrder(next);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BottomActionConfig {
  final String key;
  final String title;
  final String subtitle;
  final ValueNotifier<bool> notifier;
  final Future<void> Function(bool) onChanged;

  AppReorderableToggleItem toToggleItem() => AppReorderableToggleItem(
    itemKey: key,
    title: title,
    subtitle: subtitle,
    enabled: notifier,
    onChanged: onChanged,
  );

  const _BottomActionConfig({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.notifier,
    required this.onChanged,
  });
}
