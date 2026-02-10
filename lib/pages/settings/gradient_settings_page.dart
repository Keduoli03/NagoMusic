import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../components/index.dart';

class GradientSettingsPage extends StatefulWidget {
  const GradientSettingsPage({super.key});

  @override
  State<GradientSettingsPage> createState() => _GradientSettingsPageState();
}

class _GradientSettingsPageState extends State<GradientSettingsPage>
    with SignalsMixin {
  static const String _prefsSaturation = 'gradient_saturation';
  static const String _prefsHueShift = 'gradient_hue_shift';

  late final _saturation = createSignal(1.0);
  late final _hueShift = createSignal(0.0);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saturation = prefs.getDouble(_prefsSaturation);
    final hueShift = prefs.getDouble(_prefsHueShift);
    if (!mounted) return;
    _saturation.value = saturation ?? 1.0;
    _hueShift.value = hueShift ?? 0.0;
    _loading.value = false;
  }

  Future<void> _updateSaturation(double value) async {
    _saturation.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsSaturation, value);
  }

  Future<void> _updateHueShift(double value) async {
    _hueShift.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsHueShift, value);
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        if (_loading.value) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return AppPageScaffold(
          extendBodyBehindAppBar: true,
          appBar: const AppTopBar(
            title: '流光设置',
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              AppSettingSection(
                title: '参数配置',
                children: [
                  AppSettingSlider(
                    title: '色彩饱和度',
                    value: _saturation.value,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    valueText: '${(_saturation.value * 100).toInt()}%',
                    description: '数值越大越鲜艳，越小越灰淡',
                    onChanged: _updateSaturation,
                  ),
                  AppSettingSlider(
                    title: '色彩变幻度',
                    value: _hueShift.value,
                    min: 0.0,
                    max: 180.0,
                    divisions: 18,
                    valueText: '${_hueShift.value.toInt()}°',
                    description: '数值越大变化更强，越小更稳定',
                    onChanged: _updateHueShift,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
