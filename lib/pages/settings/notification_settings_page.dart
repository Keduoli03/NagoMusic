import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import '../../components/index.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  @override
  void initState() {
    super.initState();
    MediaNotificationSettings.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '通知设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '媒体通知',
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: MediaNotificationSettings.showLyrics,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '通知显示歌词',
                    subtitle: '在媒体通知里显示当前歌词行',
                    value: enabled,
                    onChanged: (value) {
                      MediaNotificationSettings.setShowLyrics(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: MediaNotificationSettings.lyricOnTop,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '歌词首行显示',
                    subtitle: '上方歌词，下方歌名与歌手名',
                    value: enabled,
                    onChanged: (value) {
                      MediaNotificationSettings.setLyricOnTop(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: MediaNotificationSettings.showCloseAction,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '显示关闭按钮',
                    subtitle: '在通知上展示关闭应用按钮',
                    value: enabled,
                    onChanged: (value) {
                      MediaNotificationSettings.setShowCloseAction(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: MediaNotificationSettings.showFavoriteAction,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '显示收藏按钮',
                    subtitle: '在通知上展示收藏/取消收藏',
                    value: enabled,
                    onChanged: (value) {
                      MediaNotificationSettings.setShowFavoriteAction(value);
                    },
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
