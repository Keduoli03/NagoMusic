import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../../components/index.dart';
import '../player/widgets/player_background.dart';

class PlayerAppearanceSettingsPage extends StatefulWidget {
  const PlayerAppearanceSettingsPage({super.key});

  @override
  State<PlayerAppearanceSettingsPage> createState() =>
      _PlayerAppearanceSettingsPageState();
}

class _PlayerAppearanceSettingsPageState
    extends State<PlayerAppearanceSettingsPage> {
  @override
  void initState() {
    super.initState();
    PlayerBackgroundSettings.ensureLoaded();
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
        title: '播放器外观',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '外观设置',
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
        ],
      ),
    );
  }
}
