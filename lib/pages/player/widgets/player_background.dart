import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/state/song_state.dart';

class PlayerBackgroundSettings {
  static const String _prefsPlaybackThemeMode = 'setting_playback_theme_mode';
  static const String _prefsDynamicGradientEnabled = 'dynamic_gradient_enabled';
  static const String _prefsSaturation = 'gradient_saturation';
  static const String _prefsHueShift = 'gradient_hue_shift';

  static final ValueNotifier<ThemeMode> playbackThemeMode = ValueNotifier(
    ThemeMode.system,
  );
  static final ValueNotifier<bool> dynamicGradientEnabled = ValueNotifier(
    false,
  );
  static final ValueNotifier<double> saturation = ValueNotifier(1.0);
  static final ValueNotifier<double> hueShift = ValueNotifier(0.0);

  static Future<void>? _loading;

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

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    playbackThemeMode.value = _modeFromString(
      prefs.getString(_prefsPlaybackThemeMode),
    );
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

  /// When set, the aurora/fallback base color is derived from this color instead
  /// of the current song's cover. Used by the 流光 settings preview so it follows
  /// the sample cover shown there rather than whatever song is playing.
  final Color? dominantColor;

  const PlayerBackground({
    super.key,
    required this.songSignal,
    this.dominantColor,
  });

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class PlayerTheme extends StatelessWidget {
  final Widget child;

  const PlayerTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PlayerBackgroundSettings.playbackThemeMode,
      builder: (context, _) {
        final mode = PlayerBackgroundSettings.playbackThemeMode.value;
        final brightness = playerBrightnessForMode(context, mode);
        final base = Theme.of(context);
        if (base.brightness == brightness) {
          return child;
        }
        final scheme = ColorScheme.fromSeed(
          seedColor: base.colorScheme.primary,
          brightness: brightness,
        );
        return Theme(
          data: base.copyWith(
            brightness: brightness,
            colorScheme: scheme,
            iconTheme: base.iconTheme.copyWith(color: scheme.onSurface),
            textTheme: base.textTheme.apply(
              bodyColor: scheme.onSurface,
              displayColor: scheme.onSurface,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  static const int _dominantCacheLimit = 128;
  static final Map<String, Color> _dominantCache = {};
  static final Map<String, Future<Color?>> _dominantInflight = {};

  /// 上一次成功取到的封面色，跨 State 实例保留。
  ///
  /// 没有它的话，只要这个 State 被重建（换播放器样式、页面重进），`_dominantColor`
  /// 就回到 null，背景会闪一帧品牌色再变回封面色。
  static Color? _lastResolvedDominant;

  String? _lastCoverPath;
  Color? _dominantColor = _lastResolvedDominant;

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
            final dominant =
                widget.dominantColor ?? _dominantColor ?? scheme.primary;
            final baseColor = _adjustBackground(dominant, preferLight);
            // 换歌 / 取色完成时让底色渐变过去，而不是直接跳一下。预览态
            // （dominantColor 固定）不需要动画，省掉一次无谓的补间。
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: baseColor),
              duration: widget.dominantColor != null
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOut,
              builder: (context, animated, _) {
                final color = animated ?? baseColor;
                if (dynamicEnabled) {
                  return _DynamicGradientBackground(
                    baseColor: color,
                    saturation: saturation,
                    hueShift: hueShift,
                  );
                }
                return _FallbackBackground(
                  color: Color.lerp(surface, color, 0.58) ?? surface,
                );
              },
            );
          },
        );
      },
    );
  }

  void _handleCoverChange(String? coverPath) {
    // When a fixed dominant color is supplied (e.g. the 流光 preview), the song
    // cover never drives the background, so skip the file probe entirely.
    if (widget.dominantColor != null) return;
    if (_lastCoverPath == coverPath) return;
    _lastCoverPath = coverPath;

    // 这里**不能**把 _dominantColor 清成 null。
    //
    // SongEntity 没有重载 ==，signal 走的是同一性比较，所以探测补标签、回填封面
    // 这些动作只要重新给 currentSong 赋一个新实例就会走到这里。一旦清空，下一帧
    // build 里的 `?? scheme.primary` 就会让整页闪一下主题色，等异步取色回来再变
    // 回封面色 —— 这就是播放/暂停时看到的闪烁。
    //
    // 正确做法是留住上一张封面的颜色，等新颜色算出来再换掉。
    if (coverPath == null || coverPath.isEmpty) {
      // 真的没有封面（而不是还没算出来），才回落到主题色。
      _dominantColor = null;
      return;
    }

    // 内存缓存是同步的，直接在 build 里读掉，连一帧过渡都不需要。
    // 原来这里无条件走 addPostFrameCallback，即使命中缓存也要等到下一帧。
    final cached = _dominantCache[coverPath];
    if (cached != null) {
      _dominantColor = cached;
      _lastResolvedDominant = cached;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDominantColor(coverPath);
    });
  }

  Future<void> _loadDominantColor(String coverPath) async {
    final cached = _dominantCache[coverPath];
    if (cached != null) {
      if (!mounted) return;
      _lastResolvedDominant = cached;
      setState(() => _dominantColor = cached);
      return;
    }
    final future =
        _dominantInflight[coverPath] ??
        (_dominantInflight[coverPath] = _computeDominantColor(coverPath));
    final color = await future;
    _dominantInflight.remove(coverPath);
    if (!mounted) return;
    if (_lastCoverPath != coverPath) return;
    if (color == null) {
      // 取色失败（文件被清了、解码不了）就保持现状，不要把已经好好的背景
      // 打回主题色。
      return;
    }
    if (_dominantCache.length >= _dominantCacheLimit) {
      // Insertion-ordered map: evict the oldest entry to bound memory.
      _dominantCache.remove(_dominantCache.keys.first);
    }
    _dominantCache[coverPath] = color;
    _lastResolvedDominant = color;
    setState(() => _dominantColor = color);
  }

  Future<Color?> _computeDominantColor(String coverPath) async {
    try {
      final bytes = await File(coverPath).readAsBytes();
      return averageImageColor(bytes);
    } catch (_) {
      return null;
    }
  }
}

/// Average (dominant) color of decoded image [bytes], downscaled for speed.
/// Shared by the live cover probe and the asset-based preview probe.
Future<Color?> averageImageColor(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: 40,
    targetHeight: 40,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
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
}

/// Dominant color of a bundled asset image, for previews that want the aurora to
/// follow a sample cover instead of the currently playing song.
Future<Color?> dominantColorFromAsset(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return averageImageColor(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

bool _preferLightBackground(BuildContext context, ThemeMode mode) {
  return playerBrightnessForMode(context, mode) == Brightness.light;
}

Brightness playerBrightnessForMode(BuildContext context, ThemeMode mode) {
  if (mode == ThemeMode.system) {
    return Theme.of(context).brightness;
  }
  return mode == ThemeMode.light ? Brightness.light : Brightness.dark;
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
  return Color.lerp(surface, preferLight ? Colors.white : Colors.black, 0.18)!;
}

class _FallbackBackground extends StatelessWidget {
  final Color color;

  const _FallbackBackground({required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            Color.lerp(color, scheme.surfaceContainer, 0.22) ?? color,
            Color.lerp(color, scheme.surface, 0.12) ?? color,
          ],
          stops: const [0.0, 0.55, 1.0],
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
  // ~30fps over the 22s loop. Quantizing the animation phase lets the painter's
  // shouldRepaint skip the full-screen multi-shader repaint between steps, while
  // the very slow drift stays visually smooth.
  static const int _phaseSteps = 22 * 30;

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One slow loop drives all blob drift; long period keeps it calm/premium.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t =
              (_controller.value * _phaseSteps).floorToDouble() / _phaseSteps;
          return CustomPaint(
            size: Size.infinite,
            painter: _AuroraPainter(
              t: t,
              base: widget.baseColor,
              saturation: widget.saturation,
              hueShift: widget.hueShift,
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}

/// Soft flowing "aurora" of drifting radial color blobs over a base gradient.
/// Replaces the old flat sliding linear gradient.
class _AuroraPainter extends CustomPainter {
  final double t;
  final Color base;
  final double saturation;
  final double hueShift;
  final bool isDark;

  _AuroraPainter({
    required this.t,
    required this.base,
    required this.saturation,
    required this.hueShift,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hsl = HSLColor.fromColor(base);
    final s = (hsl.saturation * saturation).clamp(0.18, 1.0);

    // Base gradient fill.
    final bgTop = hsl.withSaturation(s).toColor();
    final bgBottom = hsl
        .withSaturation((s * 0.85).clamp(0.0, 1.0))
        .withLightness(
          (hsl.lightness + (isDark ? -0.04 : 0.03)).clamp(0.0, 1.0),
        )
        .toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          bgTop,
          bgBottom,
        ]),
    );

    final colors = _palette(hsl, s);
    final blobAlpha = isDark ? 0.50 : 0.34;
    for (var i = 0; i < colors.length; i++) {
      final center = _blobCenter(i, size);
      final radius =
          size.shortestSide *
          (0.62 + 0.10 * math.sin(2 * math.pi * t + i * 1.3));
      final c = colors[i];
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            c.withValues(alpha: blobAlpha),
            c.withValues(alpha: blobAlpha * 0.45),
            c.withValues(alpha: 0.0),
          ],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(center, radius, paint);
    }
  }

  Offset _blobCenter(int i, Size size) {
    final phase = i * 1.7;
    final fx = 0.55 + i * 0.13;
    final fy = 0.70 + i * 0.11;
    final cx =
        size.width * (0.5 + 0.40 * math.sin(2 * math.pi * t * fx + phase));
    final cy =
        size.height *
        (0.45 + 0.38 * math.cos(2 * math.pi * t * fy + phase * 1.3));
    return Offset(cx, cy);
  }

  List<Color> _palette(HSLColor hsl, double s) {
    final sat = s.clamp(0.28, 1.0);
    Color mk(double deltaHue, double deltaLight) {
      return HSLColor.fromAHSL(
        1.0,
        (hsl.hue + deltaHue) % 360,
        sat,
        (hsl.lightness + deltaLight).clamp(isDark ? 0.18 : 0.62, 0.96),
      ).toColor();
    }

    final shift = hueShift.clamp(0.0, 180.0);
    return [
      mk(0, isDark ? 0.06 : 0.0),
      mk(shift, isDark ? 0.0 : 0.04),
      mk(-shift, isDark ? 0.10 : -0.02),
      mk(shift * 1.7, isDark ? 0.03 : 0.02),
    ];
  }

  @override
  bool shouldRepaint(_AuroraPainter old) {
    return old.t != t ||
        old.base != base ||
        old.saturation != saturation ||
        old.hueShift != hueShift ||
        old.isDark != isDark;
  }
}
