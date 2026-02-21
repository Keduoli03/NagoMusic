import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../app/state/settings_state.dart';
import '../../components/index.dart';

class AppAppearanceSettingsPage extends StatefulWidget {
  const AppAppearanceSettingsPage({super.key});

  @override
  State<AppAppearanceSettingsPage> createState() =>
      _AppAppearanceSettingsPageState();
}

class _AppAppearanceSettingsPageState extends State<AppAppearanceSettingsPage> {
  @override
  void initState() {
    super.initState();
    AppLayoutSettings.ensureLoaded();
    AppThemeSettings.ensureLoaded();
    AppBackgroundSettings.ensureLoaded();
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

  Future<void> _showThemeColorPickerDialog(BuildContext context) async {
    final current =
        AppThemeSettings.themeSeedColor.value ?? const Color(0xFF3B82F6);
    await showDialog(
      context: context,
      builder: (context) {
        return _ThemeColorPickerDialog(
          initialColor: current,
          onSelected: (color) {
            AppThemeSettings.setDynamicColorEnabled(false);
            AppThemeSettings.setThemeSeedColor(color);
          },
        );
      },
    );
  }

  Widget _presetColorItem({
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }

  Future<void> _showBackgroundImageSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('选择图片'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    allowMultiple: false,
                  );
                  final file = result?.files.first;
                  if (file?.path == null) return;
                  await AppBackgroundSettings.setBackgroundImagePath(
                    file!.path!,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('清除背景'),
                onTap: () async {
                  Navigator.pop(context);
                  await AppBackgroundSettings.setBackgroundImagePath(null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '应用外观',
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
              ValueListenableBuilder<bool>(
                valueListenable: AppThemeSettings.dynamicColorEnabled,
                builder: (context, enabled, _) {
                  return ValueListenableBuilder<Color?>(
                    valueListenable: AppThemeSettings.themeSeedColor,
                    builder: (context, seedColor, _) {
                      final colors = [
                        const Color(0xFF3B82F6),
                        const Color(0xFF22C55E),
                        const Color(0xFFA855F7),
                        const Color(0xFFF97316),
                        const Color(0xFFEF4444),
                        const Color(0xFFEC4899),
                        const Color(0xFF14B8A6),
                        const Color(0xFF6366F1),
                      ];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '主题色',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              enabled ? '已启用系统动态颜色' : '设置应用主色调',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 44,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  if (seedColor != null &&
                                      !colors.any(
                                        (c) =>
                                            c.toARGB32() ==
                                            seedColor.toARGB32(),
                                      )) ...[
                                    _presetColorItem(
                                      selected: true,
                                      onTap: () {},
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: seedColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  _presetColorItem(
                                    selected: false,
                                    onTap: () => _showThemeColorPickerDialog(
                                      context,
                                    ),
                                    child: Icon(
                                      Icons.palette_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  for (final color in colors) ...[
                                    _presetColorItem(
                                      selected: seedColor?.toARGB32() ==
                                          color.toARGB32(),
                                      onTap: () =>
                                          AppThemeSettings.setDynamicColorEnabled(
                                        false,
                                      ).then(
                                        (_) =>
                                            AppThemeSettings.setThemeSeedColor(
                                          color,
                                        ),
                                      ),
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  _presetColorItem(
                                    selected: seedColor == null,
                                    onTap: () =>
                                        AppThemeSettings.setDynamicColorEnabled(
                                      false,
                                    ).then(
                                      (_) => AppThemeSettings.setThemeSeedColor(
                                        null,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.refresh_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
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
              ValueListenableBuilder<String?>(
                valueListenable: AppBackgroundSettings.backgroundImagePath,
                builder: (context, pathValue, _) {
                  final name = pathValue == null || pathValue.isEmpty
                      ? '未设置'
                      : path.basename(pathValue);
                  return AppSettingTile(
                    title: '自定义背景',
                    subtitle: name,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showBackgroundImageSheet(context),
                  );
                },
              ),
              ValueListenableBuilder<double>(
                valueListenable: AppBackgroundSettings.backgroundMaskOpacity,
                builder: (context, value, _) {
                  return AppSettingSlider(
                    title: '图片透明度',
                    value: (value * 100).clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueText: '${(value * 100).round()}%',
                    onChanged: (next) {
                      AppBackgroundSettings.setBackgroundMaskOpacity(
                        next / 100,
                      );
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

class _ThemeColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onSelected;

  const _ThemeColorPickerDialog({
    required this.initialColor,
    required this.onSelected,
  });

  @override
  State<_ThemeColorPickerDialog> createState() =>
      _ThemeColorPickerDialogState();
}

class _ThemeColorPickerDialogState extends State<_ThemeColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _updateSaturationValue(Offset localPosition, double size) {
    final dx = localPosition.dx.clamp(0.0, size);
    final dy = localPosition.dy.clamp(0.0, size);
    final saturation = (dx / size).clamp(0.0, 1.0);
    final value = (1 - dy / size).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withSaturation(saturation).withValue(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _hsv.toColor();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '调色板',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: preview,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth;
                  return GestureDetector(
                    onPanDown: (details) =>
                        _updateSaturationValue(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _updateSaturationValue(details.localPosition, size),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: size,
                          height: size,
                          child: CustomPaint(
                            painter: _SaturationValuePainter(
                              hue: _hsv.hue,
                            ),
                          ),
                        ),
                        Positioned(
                          left: _hsv.saturation * size - 10,
                          top: (1 - _hsv.value) * size - 10,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.onSurface,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _RainbowHueSlider(
                value: _hsv.hue,
                onChanged: (value) {
                  setState(() {
                    _hsv = _hsv.withHue(value);
                  });
                },
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onSelected(preview);
                      Navigator.pop(context);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  final double hue;

  _SaturationValuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, baseColor],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
    final overlay = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
      ).createShader(rect);
    canvas.drawRect(rect, overlay);
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

class _RainbowHueSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _RainbowHueSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_RainbowHueSlider> createState() => _RainbowHueSliderState();
}

class _RainbowHueSliderState extends State<_RainbowHueSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayValue = _dragValue ?? widget.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) => _updateValue(details.localPosition.dx, width),
          onPanUpdate: (details) =>
              _updateValue(details.localPosition.dx, width),
          onPanEnd: (_) => setState(() => _dragValue = null),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (displayValue / 360 * width) - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, displayValue, 1, 1)
                          .toColor(),
                      border: Border.all(
                        color: scheme.onSurface,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateValue(double dx, double width) {
    final clamped = dx.clamp(0.0, width);
    final next = (clamped / width * 360).clamp(0.0, 360.0);
    setState(() {
      _dragValue = next;
    });
    widget.onChanged(next);
  }
}
