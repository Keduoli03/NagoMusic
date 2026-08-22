import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../app/services/haptic_service.dart';
import '../../app/state/settings_state.dart';
import '../../app/theme/app_colors.dart';
import '../../components/index.dart';
import '../../components/layout/liquid_glass.dart';

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
    SongListDisplaySettings.ensureLoaded();
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

  Future<void> _showHapticLevelSheet(
    BuildContext context,
    HapticLevel current,
  ) async {
    const options = [
      (HapticLevel.standard, '标准', '按操作语义原样触发'),
      (HapticLevel.light, '轻柔', '所有震动整体降一级'),
      (HapticLevel.off, '关闭', '不再有任何震动反馈'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return AppSheetPanel(
          title: '触感反馈',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (level, label, desc) in options)
                AppSettingTile(
                  title: label,
                  subtitle: desc,
                  trailing: level == current
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    // setLevel 自己会震一下作为预览，所以不用再补 Haptics 调用。
                    Haptics.setLevel(level);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showBackgroundImageSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('选择图片'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _pickAndCropBackground(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('清除背景'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await AppBackgroundSettings.setBackgroundImagePath(null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Pick a source image, launch the uCrop editor with the aspect ratio of the
  /// current device screen, and save the cropped output as the new background.
  Future<void> _pickAndCropBackground(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final file = result?.files.first;
    if (file?.path == null) return;

    // Use the device's short/long dimensions so the crop frame matches what
    // the wallpaper will actually be painted into. Reading it once here is
    // fine — no need to react to rotation while the cropper UI is on screen.
    if (!context.mounted) return;
    final size = MediaQuery.of(context).size;
    final ratio = CropAspectRatio(ratioX: size.width, ratioY: size.height);

    final cropped = await ImageCropper().cropImage(
      sourcePath: file!.path!,
      compressFormat: ImageCompressFormat.png,
      compressQuality: 95,
      aspectRatio: ratio,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪背景',
          hideBottomControls: true,
          lockAspectRatio: true,
          // Explicit toolbar / status bar tint so the confirm/cancel icons
          // never blend into the phone's system bar (which was the "点几下才
          // 点得到" bug on notched screens).
          toolbarColor: const Color(0xFF212121),
          statusBarLight: false,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.white,
          backgroundColor: Colors.black,
        ),
        IOSUiSettings(
          title: '裁剪背景',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return;

    // uCrop writes to a cache directory that OS may sweep; copy the output
    // into our app documents dir so the background survives across launches.
    final docs = await getApplicationDocumentsDirectory();
    final targetPath = path.join(
      docs.path,
      'background_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(cropped.path).copy(targetPath);
    await AppBackgroundSettings.setBackgroundImagePath(targetPath);
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
            title: '导航布局',
            children: [
              ValueListenableBuilder<AppNavigationStyle>(
                valueListenable: AppLayoutSettings.navigationStyle,
                builder: (context, style, _) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导航方式',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AppNavigationStyle>(
                            segments: const [
                              ButtonSegment(
                                value: AppNavigationStyle.drawer,
                                icon: Icon(Icons.menu_open_rounded),
                                label: Text('侧边栏'),
                              ),
                              ButtonSegment(
                                value: AppNavigationStyle.bottomBar,
                                icon: Icon(Icons.space_dashboard_outlined),
                                label: Text('底部导航'),
                              ),
                            ],
                            selected: {style},
                            showSelectedIcon: false,
                            onSelectionChanged: (selection) {
                              AppLayoutSettings.setNavigationStyle(
                                selection.first,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          style == AppNavigationStyle.bottomBar
                              ? '四个常用入口固定在底部，专辑、艺术家与文件夹仍从音乐库进入'
                              : '保留当前从左侧菜单访问各页面的方式',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                valueListenable: SongListDisplaySettings.showQualityTag,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '显示音质标签',
                    subtitle: '在歌曲列表标题旁显示 Hi-Res / 无损 / HQ',
                    value: enabled,
                    onChanged: (value) {
                      SongListDisplaySettings.setShowQualityTag(value);
                    },
                  );
                },
              ),
              ValueListenableBuilder<AppBottomBarStyle>(
                valueListenable: AppLayoutSettings.bottomBarStyle,
                builder: (context, style, _) {
                  final glass = style == AppBottomBarStyle.liquidGlass;
                  return AppSettingSwitchTile(
                    title: '液态玻璃底栏',
                    subtitle: glass ? '底栏透出并折射身后的内容' : '底栏使用不透明实底',
                    value: glass,
                    onChanged: (value) {
                      AppLayoutSettings.setBottomBarStyle(
                        value
                            ? AppBottomBarStyle.liquidGlass
                            : AppBottomBarStyle.standard,
                      );
                      if (value) LiquidGlassSupport.ensureLoaded();
                    },
                  );
                },
              ),
              ValueListenableBuilder<HapticLevel>(
                valueListenable: Haptics.levelListenable,
                builder: (context, level, _) {
                  return AppSettingNavTile(
                    title: '触感反馈',
                    subtitle: '拨开关、切 Tab 等操作时的震动强度',
                    value: switch (level) {
                      HapticLevel.off => '关闭',
                      HapticLevel.light => '轻柔',
                      HapticLevel.standard => '标准',
                    },
                    onTap: () => _showHapticLevelSheet(context, level),
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
                        // 第一个是 kBrand —— 没选过主题色时的默认值，
                        // 放在首位这样默认状态下能看出选中的是哪一个。
                        kBrand,
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
                                    onTap: () =>
                                        _showThemeColorPickerDialog(context),
                                    child: Icon(
                                      Icons.palette_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  for (final color in colors) ...[
                                    _presetColorItem(
                                      selected:
                                          seedColor?.toARGB32() ==
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
                                          (_) =>
                                              AppThemeSettings.setThemeSeedColor(
                                                null,
                                              ),
                                        ),
                                    child: Icon(
                                      Icons.refresh_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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
                  return ThemeModeSelector(
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
                  final hasImage =
                      pathValue != null && pathValue.trim().isNotEmpty;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSettingNavTile(
                        title: '自定义背景',
                        subtitle: name,
                        onTap: () => _showBackgroundImageSheet(context),
                      ),
                      if (hasImage)
                        ValueListenableBuilder<double>(
                          valueListenable:
                              AppBackgroundSettings.backgroundMaskOpacity,
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
                      if (hasImage)
                        ValueListenableBuilder<double>(
                          valueListenable:
                              AppBackgroundSettings.backgroundBlurSigma,
                          builder: (context, sigma, _) {
                            return AppSettingSlider(
                              title: '图片模糊',
                              description: '0 = 保持原图清晰',
                              value: sigma.clamp(0, 32),
                              min: 0,
                              max: 32,
                              divisions: 32,
                              valueText: sigma.toStringAsFixed(0),
                              onChanged: (next) {
                                AppBackgroundSettings.setBackgroundBlurSigma(
                                  next,
                                );
                              },
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
              ValueListenableBuilder<double>(
                valueListenable: AppBackgroundSettings.panelOpacity,
                builder: (context, value, _) {
                  // Slider shows *transparency* (what the label says), while
                  // storage keeps *opacity*. Invert on the way in/out so the
                  // user's mental model matches: 100% = fully see-through,
                  // 0% = solid panel.
                  final transparencyPercent = ((1 - value) * 100).clamp(0, 100);
                  return AppSettingSlider(
                    title: '面板透明度',
                    description: '调节卡片、列表面板等半透明程度（100% = 完全透明）',
                    value: transparencyPercent.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueText: '${transparencyPercent.round()}%',
                    onChanged: (next) {
                      final opacity = (1 - next / 100).clamp(0.0, 1.0);
                      AppBackgroundSettings.setPanelOpacity(opacity);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppBackgroundSettings.pageGlowEnabled,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '页面流光',
                    subtitle: enabled ? '页面顶部叠加主题色柔和渐变' : '关闭后页面仅使用主题背景',
                    value: enabled,
                    onChanged: (value) {
                      AppBackgroundSettings.setPageGlowEnabled(value);
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
                  Text('调色板', style: Theme.of(context).textTheme.titleMedium),
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
                            painter: _SaturationValuePainter(hue: _hsv.hue),
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

  const _RainbowHueSlider({required this.value, required this.onChanged});

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
                      color: HSVColor.fromAHSV(1, displayValue, 1, 1).toColor(),
                      border: Border.all(color: scheme.onSurface, width: 2),
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
