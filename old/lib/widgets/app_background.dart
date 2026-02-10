import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

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

    return Container(
      decoration: BoxDecoration(gradient: background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!isDark)
            _glow(
              alignment: Alignment.topRight,
              size: 260,
              colors: const [
                Color(0x66FDE2A7),
                Color(0x00FDE2A7),
              ],
            ),
          if (!isDark)
            _glow(
              alignment: Alignment.bottomLeft,
              size: 240,
              colors: const [
                Color(0x66CBE8FF),
                Color(0x00CBE8FF),
              ],
            ),
          child,
        ],
      ),
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
