import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../components/index.dart';
import '../player/widgets/player_background.dart';

class GradientSettingsPage extends StatefulWidget {
  const GradientSettingsPage({super.key});

  @override
  State<GradientSettingsPage> createState() => _GradientSettingsPageState();
}

class _GradientSettingsPageState extends State<GradientSettingsPage>
    with SignalsMixin {
  late final _saturation = createSignal(1.0);
  late final _hueShift = createSignal(0.0);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await PlayerBackgroundSettings.ensureLoaded();
    if (!mounted) return;
    _saturation.value = PlayerBackgroundSettings.saturation.value;
    _hueShift.value = PlayerBackgroundSettings.hueShift.value;
    _loading.value = false;
  }

  void _updateSaturation(double value) {
    _saturation.value = value;
    PlayerBackgroundSettings.setSaturation(value);
  }

  void _updateHueShift(double value) {
    _hueShift.value = value;
    PlayerBackgroundSettings.setHueShift(value);
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
