import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../viewmodels/player_viewmodel.dart';
import '../../widgets/labeled_slider.dart';

class GradientSettingsPage extends StatelessWidget {
  const GradientSettingsPage({super.key});

  List<Widget> _withDividers(List<Widget> items) {
    if (items.isEmpty) return items;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(items[i]);
      if (i != items.length - 1) {
        children.add(const SizedBox(height: 6));
      }
    }
    return children;
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white70 : Colors.black87;
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark
        ? const Color.fromARGB(28, 0, 0, 0)
        : const Color.fromARGB(15, 0, 0, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: _withDividers(items)),
        ),
      ],
    );
  }

  Widget _glow({
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1C1F24),
              Color(0xFF22262C),
              Color(0xFF1B1D22),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF6F7FB),
              Color(0xFFF7F3E8),
              Color(0xFFF1F7F4),
            ],
          );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('流光设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: [
                  const Color(0x66FDE2A7),
                  const Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: [
                  const Color(0x66CBE8FF),
                  const Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _sectionCard(
                    context,
                    '参数配置',
                    [
                      Watch.builder(builder: (context) {
                        final vm = PlayerViewModel();
                        watchSignal(context, vm.uiTick);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LabeledSlider(
                                title: '色彩饱和度',
                                value: vm.dynamicGradientSaturation,
                                min: 0.0,
                                max: 2.0,
                                divisions: 20,
                                tickCount: 11,
                                valueText:
                                    '${(vm.dynamicGradientSaturation * 100).toInt()}%',
                                description: '数值越大越鲜艳，越小越灰淡',
                                label:
                                    '${(vm.dynamicGradientSaturation * 100).toInt()}%',
                                onChanged: vm.setDynamicGradientSaturation,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                              const SizedBox(height: 12),
                              LabeledSlider(
                                title: '色彩变幻度',
                                value: vm.dynamicGradientHueShift,
                                min: 0.0,
                                max: 180.0,
                                divisions: 18,
                                tickCount: 19,
                                valueText: '${vm.dynamicGradientHueShift.toInt()}°',
                                description: '数值越大变化更强，越小更稳定',
                                label: '${vm.dynamicGradientHueShift.toInt()}°',
                                onChanged: vm.setDynamicGradientHueShift,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                              ),
                            ],
                          ),
                        );
                      },),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
