import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';

class PlayerBackgroundSettings {
  static const String _prefsPlaybackThemeMode = 'setting_playback_theme_mode';
  static const String _prefsDynamicGradientEnabled = 'dynamic_gradient_enabled';
  static const String _prefsSaturation = 'gradient_saturation';
  static const String _prefsHueShift = 'gradient_hue_shift';

  static final ValueNotifier<ThemeMode> playbackThemeMode =
      ValueNotifier(ThemeMode.system);
  static final ValueNotifier<bool> dynamicGradientEnabled =
      ValueNotifier(false);
  static final ValueNotifier<double> saturation = ValueNotifier(1.0);
  static final ValueNotifier<double> hueShift = ValueNotifier(0.0);

  static bool _loaded = false;

  static ThemeMode _modeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    playbackThemeMode.value =
        _modeFromString(prefs.getString(_prefsPlaybackThemeMode));
    dynamicGradientEnabled.value =
        prefs.getBool(_prefsDynamicGradientEnabled) ?? false;
    saturation.value = prefs.getDouble(_prefsSaturation) ?? 1.0;
    hueShift.value = prefs.getDouble(_prefsHueShift) ?? 0.0;
  }

  static Future<void> setPlaybackThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPlaybackThemeMode, _modeToString(mode));
    playbackThemeMode.value = mode;
  }

  static Future<void> setDynamicGradientEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDynamicGradientEnabled, enabled);
    dynamicGradientEnabled.value = enabled;
  }

  static Future<void> setSaturation(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsSaturation, value);
    saturation.value = value;
  }

  static Future<void> setHueShift(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsHueShift, value);
    hueShift.value = value;
  }
}

class PlayerBackground extends StatefulWidget {
  final Signal<SongEntity?> songSignal;

  const PlayerBackground({super.key, required this.songSignal});

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  static final Map<String, Color> _dominantCache = {};
  static final Map<String, Future<Color?>> _dominantInflight = {};

  String? _lastCoverPath;
  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    PlayerBackgroundSettings.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Watch.builder(
      builder: (context) {
        final song = widget.songSignal.value;
        final coverPath = song?.localCoverPath;
        final hasCover = coverPath != null && coverPath.isNotEmpty;
        _handleCoverChange(coverPath);
        return AnimatedBuilder(
          animation: Listenable.merge([
            PlayerBackgroundSettings.playbackThemeMode,
            PlayerBackgroundSettings.dynamicGradientEnabled,
            PlayerBackgroundSettings.saturation,
            PlayerBackgroundSettings.hueShift,
          ]),
          builder: (context, _) {
            final playbackMode =
                PlayerBackgroundSettings.playbackThemeMode.value;
            final dynamicEnabled =
                PlayerBackgroundSettings.dynamicGradientEnabled.value;
            final saturation = PlayerBackgroundSettings.saturation.value;
            final hueShift = PlayerBackgroundSettings.hueShift.value;
            final preferLight = _preferLightBackground(context, playbackMode);
            final surface = _tintSurface(scheme.surface, preferLight);
            final dominant = _dominantColor ?? scheme.primary;
            final baseColor = _adjustBackground(dominant, preferLight);
            if (dynamicEnabled) {
              return _DynamicGradientBackground(
                baseColor: baseColor,
                saturation: saturation,
                hueShift: hueShift,
              );
            }
            final overlayColor = surface.withValues(
              alpha: preferLight ? 0.72 : 0.8,
            );
            return Stack(
              children: [
                if (hasCover)
                  Positioned.fill(
                    child: Image.file(
                      File(coverPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) {
                        return _FallbackBackground(color: surface);
                      },
                    ),
                  )
                else
                  _FallbackBackground(color: surface),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(color: overlayColor),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleCoverChange(String? coverPath) {
    if (_lastCoverPath == coverPath) return;
    _lastCoverPath = coverPath;
    _dominantColor = null;
    if (coverPath == null || coverPath.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDominantColor(coverPath);
    });
  }

  Future<void> _loadDominantColor(String coverPath) async {
    final cached = _dominantCache[coverPath];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _dominantColor = cached);
      return;
    }
    final future = _dominantInflight[coverPath] ??
        (_dominantInflight[coverPath] = _computeDominantColor(coverPath));
    final color = await future;
    _dominantInflight.remove(coverPath);
    if (!mounted) return;
    if (_lastCoverPath != coverPath) return;
    if (color != null) {
      _dominantCache[coverPath] = color;
    }
    setState(() => _dominantColor = color);
  }

  Future<Color?> _computeDominantColor(String coverPath) async {
    try {
      final bytes = await File(coverPath).readAsBytes();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final list = data.buffer.asUint8List();
      int r = 0;
      int g = 0;
      int b = 0;
      int count = 0;
      for (var i = 0; i + 3 < list.length; i += 4) {
        final a = list[i + 3];
        if (a < 10) continue;
        r += list[i];
        g += list[i + 1];
        b += list[i + 2];
        count += 1;
      }
      if (count == 0) return null;
      return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    } catch (_) {
      return null;
    }
  }
}

bool _preferLightBackground(BuildContext context, ThemeMode mode) {
  if (mode == ThemeMode.system) {
    return Theme.of(context).brightness == Brightness.light;
  }
  return mode == ThemeMode.light;
}

Color _adjustBackground(Color color, bool preferLightBackground) {
  final hsl = HSLColor.fromColor(color);
  var lightness = hsl.lightness;
  if (preferLightBackground) {
    if (lightness < 0.78) {
      lightness = 0.78;
    }
    if (lightness > 0.92) {
      lightness = 0.92;
    }
  } else {
    if (lightness > 0.32) {
      lightness = 0.32;
    }
    if (lightness < 0.18) {
      lightness = 0.18;
    }
  }
  return hsl.withLightness(lightness).toColor();
}

Color _tintSurface(Color surface, bool preferLight) {
  return Color.lerp(
    surface,
    preferLight ? Colors.white : Colors.black,
    0.18,
  )!;
}

class _FallbackBackground extends StatelessWidget {
  final Color color;

  const _FallbackBackground({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.75),
            color.withValues(alpha: 0.85),
          ],
        ),
      ),
    );
  }
}

class _DynamicGradientBackground extends StatefulWidget {
  final Color baseColor;
  final double saturation;
  final double hueShift;

  const _DynamicGradientBackground({
    required this.baseColor,
    required this.saturation,
    required this.hueShift,
  });

  @override
  State<_DynamicGradientBackground> createState() =>
      _DynamicGradientBackgroundState();
}

class _DynamicGradientBackgroundState extends State<_DynamicGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _generateColors(Color base) {
    final hsl = HSLColor.fromColor(base);
    final s = (hsl.saturation * widget.saturation).clamp(0.0, 1.0);
    final adjustedBase = hsl.withSaturation(s);
    final shift = widget.hueShift;
    final c1 =
        adjustedBase.withHue((adjustedBase.hue + shift) % 360).toColor();
    final c2 =
        adjustedBase.withHue((adjustedBase.hue - shift) % 360).toColor();
    return [adjustedBase.toColor(), c1, c2, adjustedBase.toColor()];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _generateColors(widget.baseColor);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment(-1.0 + _controller.value, -1.0),
              end: Alignment(1.0 - _controller.value, 1.0),
              tileMode: TileMode.mirror,
            ),
          ),
        );
      },
    );
  }
}
