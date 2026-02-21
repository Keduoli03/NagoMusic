import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../../../app/state/settings_state.dart';

class AppBackground extends StatefulWidget {
  final Widget child;

  const AppBackground({
    super.key,
    required this.child,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  @override
  void initState() {
    super.initState();
    AppBackgroundSettings.ensureLoaded();
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

    return AnimatedBuilder(
      animation: Listenable.merge([
        AppBackgroundSettings.backgroundImagePath,
        AppBackgroundSettings.backgroundMaskOpacity,
      ]),
      builder: (context, _) {
        final path = AppBackgroundSettings.backgroundImagePath.value;
        final maskOpacity =
            AppBackgroundSettings.backgroundMaskOpacity.value;
        final imagePath = path;
        final hasImage = imagePath != null &&
            imagePath.isNotEmpty &&
            File(imagePath).existsSync();
        final maskColor = Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: maskOpacity);
        return Container(
          decoration: BoxDecoration(gradient: background),
          child: Stack(
            children: [
              if (hasImage)
                Positioned.fill(
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                  ),
                ),
              if (!hasImage && !isDark)
                _glow(
                  alignment: Alignment.topRight,
                  size: 260,
                  colors: const [
                    Color(0x66FDE2A7),
                    Color(0x00FDE2A7),
                  ],
                ),
              if (!hasImage && !isDark)
                _glow(
                  alignment: Alignment.bottomLeft,
                  size: 240,
                  colors: const [
                    Color(0x66CBE8FF),
                    Color(0x00CBE8FF),
                  ],
                ),
              if (hasImage && maskOpacity > 0)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(color: maskColor),
                  ),
                ),
              widget.child,
            ],
          ),
        );
      },
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
}
