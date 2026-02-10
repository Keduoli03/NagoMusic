import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../models/music_entity.dart';
import '../utils/lyrics_parser.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/labeled_slider.dart';
import '../widgets/lyrics/lyrics_viewer.dart';
import '../widgets/marquee_text.dart';
import '../widgets/song_detail_sheet.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchToLyrics() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showLyricsSettings(BuildContext context, PlayerViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Watch((context) {
          watchSignal(context, vm.lyricsTick);
          watchSignal(context, vm.playbackTick);
          watchSignal(context, vm.uiTick);

          final scheme = Theme.of(context).colorScheme;
          final playbackMode = vm.playbackThemeMode;
          final dominantColor = vm.dominantColor;
          final preferLightBackground = _preferLightBackground(context, playbackMode);
          final useDarkText = _useDarkText(dominantColor, preferLightBackground);
          final textColor = _primaryTextColor(useDarkText);
          final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
          final maskColor = preferLightBackground
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.28);
          final dividerColor = secondaryTextColor.withValues(alpha: 0.2);

          final newTheme = Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.apply(
                  bodyColor: textColor,
                  displayColor: textColor,
                ),
            iconTheme: IconThemeData(color: textColor),
            listTileTheme: ListTileThemeData(
              textColor: textColor,
              iconColor: textColor,
            ),
            dividerColor: dividerColor,
            colorScheme: scheme.copyWith(
              onSurface: textColor,
              onSurfaceVariant: secondaryTextColor,
              secondaryContainer: textColor.withValues(alpha: 0.2),
              onSecondaryContainer: textColor,
              outline: dividerColor,
            ),
          );

          return Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: RepaintBoundary(child: _PlayerBackground()),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(color: maskColor),
                      ),
                    ),
                  ),
                  Theme(
                    data: newTheme,
                    child: Material(
                      color: Colors.transparent,
                      child: SafeArea(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  height: 4,
                                  width: 32,
                                  margin: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: dividerColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  '歌词设置',
                                  style: newTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 8),
                              LabeledSlider(
                                title: '字号',
                                value: vm.lyricsFontSize,
                                min: 14.0,
                                max: 32.0,
                                divisions: 9,
                                label: vm.lyricsFontSize.toStringAsFixed(0),
                                valueText: vm.lyricsFontSize.toStringAsFixed(0),
                                onChanged: (value) {
                                  vm.setLyricsFontSize(value);
                                },
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              LabeledSlider(
                                title: '播放字号',
                                value: vm.lyricsActiveFontSize,
                                min: 16.0,
                                max: 48.0,
                                divisions: 16,
                                label: vm.lyricsActiveFontSize.toStringAsFixed(0),
                                valueText: vm.lyricsActiveFontSize.toStringAsFixed(0),
                                onChanged: (value) {
                                  vm.setLyricsActiveFontSize(value);
                                },
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              LabeledSlider(
                                title: '行距',
                                value: vm.lyricsLineGap,
                                min: 8.0,
                                max: 32.0,
                                divisions: 12,
                                label: vm.lyricsLineGap.toStringAsFixed(0),
                                valueText: vm.lyricsLineGap.toStringAsFixed(0),
                                onChanged: (value) {
                                  vm.setLyricsLineGap(value);
                                },
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '对齐',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: SegmentedButton<String>(
                                        segments: const [
                                          ButtonSegment(
                                            value: 'left',
                                            label: Text('居左'),
                                            icon: Icon(Icons.format_align_left),
                                          ),
                                          ButtonSegment(
                                            value: 'center',
                                            label: Text('居中'),
                                            icon: Icon(Icons.format_align_center),
                                          ),
                                          ButtonSegment(
                                            value: 'right',
                                            label: Text('居右'),
                                            icon: Icon(Icons.format_align_right),
                                          ),
                                        ],
                                        selected: {vm.lyricsAlignment},
                                        onSelectionChanged: (Set<String> newSelection) {
                                          vm.setLyricsAlignment(newSelection.first);
                                        },
                                        showSelectedIcon: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '三行歌词对齐',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: SegmentedButton<String>(
                                        segments: const [
                                          ButtonSegment(
                                            value: 'left',
                                            label: Text('居左'),
                                            icon: Icon(Icons.format_align_left),
                                          ),
                                          ButtonSegment(
                                            value: 'center',
                                            label: Text('居中'),
                                            icon: Icon(Icons.format_align_center),
                                          ),
                                          ButtonSegment(
                                            value: 'right',
                                            label: Text('居右'),
                                            icon: Icon(Icons.format_align_right),
                                          ),
                                        ],
                                        selected: {vm.miniLyricsAlignment},
                                        onSelectionChanged: (Set<String> newSelection) {
                                          vm.setMiniLyricsAlignment(newSelection.first);
                                        },
                                        showSelectedIcon: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SwitchListTile(
                                title: const Text('拖动调节进度'),
                                value: vm.lyricsDragToSeek,
                                onChanged: (value) {
                                  vm.setLyricsDragToSeek(value);
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                              ),
                              SwitchListTile(
                                title: const Text('强制逐字'),
                                subtitle: const Text('对非逐字歌词进行逐字处理'),
                                value: vm.lyricsKaraokeEnabled,
                                onChanged: (value) {
                                  vm.setLyricsKaraokeEnabled(value);
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const _PlayerBackground(),
          SafeArea(
            child: Column(
              children: [
                const _PlayerHeader(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: [
                      _PlayerControlView(onTapLyrics: _switchToLyrics),
                      Watch.builder(
                        builder: (context) {
                          final vm = PlayerViewModel();
                          watchSignal(context, vm.lyricsTick);
                          watchSignal(context, vm.playbackTick);
                          watchSignal(context, vm.queueTick);
                          watchSignal(context, vm.uiTick);
                          final hasTranslation = vm.lyricsTranslation != null && vm.lyricsTranslation!.isNotEmpty;
                          final showTranslation = vm.showLyricsTranslation;
                          final useDarkText = _useDarkText(vm.dominantColor, _preferLightBackground(context, vm.playbackThemeMode));
                          final textColor = _primaryTextColor(useDarkText);

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: LyricsViewer(
                                  lyrics: vm.lyrics ?? '',
                                  translation: vm.lyricsTranslation,
                                  lyricModel: vm.lyricsKaraokeEnabled ? vm.lyricModel : null,
                                  position: vm.position,
                                  dominantColor: vm.dominantColor,
                                  fontSize: vm.lyricsFontSize,
                                  lineGap: vm.lyricsLineGap,
                                  alignment: vm.lyricsAlignment,
                                  activeFontSize: vm.lyricsActiveFontSize,
                                  enableDrag: vm.lyricsDragToSeek,
                                  onSeek: (d) => vm.seek(d),
                                  showTranslationText: showTranslation,
                                  isPlaying: vm.isPlaying,
                                ),
                              ),
                              Positioned(
                                left: 24,
                                right: 24,
                                bottom: 48,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _LyricsBadge(
                                      text: '词',
                                      onTap: () => _showLyricsSettings(context, vm),
                                      color: textColor,
                                    ),
                                    if (hasTranslation)
                                      _LyricsBadge(
                                        text: '译',
                                        isActive: showTranslation,
                                        onTap: () => vm.setShowLyricsTranslation(!showTranslation),
                                        color: textColor,
                                        filled: true,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsBadge extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isActive;
  final Color color;
  final bool filled;

  const _LyricsBadge({
    required this.text,
    required this.onTap,
    this.isActive = true,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    // If filled & active: Background is 'color', Text is Inverse of 'color'.
    // Else: Background is Transparent, Text/Border is 'color'.
    final isSelected = filled && isActive;
    
    // Content color (Text & Border for unselected, Text for selected)
    // If selected, text should contrast with the filled background (which is 'color').
    final contentColor = isSelected 
        ? (color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent, // Hit test area
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.transparent : contentColor, 
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: contentColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
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

bool _preferLightBackground(BuildContext context, ThemeMode mode) {
  if (mode == ThemeMode.system) {
    return Theme.of(context).brightness == Brightness.light;
  }
  return mode == ThemeMode.light;
}

bool _useDarkText(Color dominantColor, bool preferLightBackground) {
  return preferLightBackground || dominantColor.computeLuminance() >= 0.6;
}

Color _primaryTextColor(bool useDarkText) {
  return useDarkText ? const Color(0xFF1B1B1B) : Colors.white;
}

Color _secondaryTextColor(bool useDarkText, double alpha) {
  return _primaryTextColor(useDarkText).withValues(alpha: alpha);
}

class _PlayerBackground extends StatelessWidget {
  const _PlayerBackground();

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.uiTick);
      final dominantColor = vm.dominantColor;
      final playbackMode = vm.playbackThemeMode;
      final preferLightBackground = _preferLightBackground(context, playbackMode);
      final bgColor = _adjustBackground(dominantColor, preferLightBackground);
      final overlayColor = preferLightBackground
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.32);

      final dynamicGradientEnabled = vm.dynamicGradientEnabled;

      if (dynamicGradientEnabled) {
        final saturation = vm.dynamicGradientSaturation;
        final hueShift = vm.dynamicGradientHueShift;
        return _DynamicGradientBackground(
          baseColor: bgColor,
          saturation: saturation,
          hueShift: hueShift,
        );
      }

      return Stack(
        children: [
          Positioned.fill(
            child: Container(color: bgColor),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    bgColor.withValues(alpha: 0.95),
                    overlayColor,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ],
      );
    },);
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
  State<_DynamicGradientBackground> createState() => _DynamicGradientBackgroundState();
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
    // Apply saturation adjustment
    final s = (hsl.saturation * widget.saturation).clamp(0.0, 1.0);
    final adjustedBase = hsl.withSaturation(s);
    
    // Generate variations by shifting hue
    final shift = widget.hueShift;
    final c1 = adjustedBase.withHue((adjustedBase.hue + shift) % 360).toColor();
    final c2 = adjustedBase.withHue((adjustedBase.hue - shift) % 360).toColor();
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

class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader();

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.uiTick);
      final dominantColor = vm.dominantColor;
      final title = vm.title;
      final artist = vm.artist;
      final playbackMode = vm.playbackThemeMode;
      final preferLightBackground = _preferLightBackground(context, playbackMode);
      final useDarkText = _useDarkText(dominantColor, preferLightBackground);
      final titleColor = _primaryTextColor(useDarkText);
      final subtitleColor = _secondaryTextColor(useDarkText, 0.7);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MarqueeText(
                    title ?? '未知歌曲',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    velocity: 40,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist ?? '未知歌手',
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // IconButton(
            //   icon: Icon(Icons.sensors, color: iconColor),
            //   onPressed: () {},
            // ),
          ],
        ),
      );
    },);
  }
}

class _PlayerControlView extends StatefulWidget {
  final VoidCallback onTapLyrics;

  const _PlayerControlView({
    required this.onTapLyrics,
  });

  @override
  State<_PlayerControlView> createState() => _PlayerControlViewState();
}

class _PlayerControlViewState extends State<_PlayerControlView> {
  bool _isSeeking = false;
  double _seekValue = 0;

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.playbackTick);
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.lyricsTick);
      watchSignal(context, vm.uiTick);
      watchSignal(context, vm.sleepTick);
      final dominantColor = vm.dominantColor;
      final preferLightBackground =
          _preferLightBackground(context, vm.playbackThemeMode);
      final useDarkText = _useDarkText(dominantColor, preferLightBackground);
      
      final lyricText = vm.lyrics ?? '';
      final hasLyrics = lyricText.trim().isNotEmpty;
      final titleColor = _primaryTextColor(useDarkText);
      final iconColor = _secondaryTextColor(useDarkText, 0.85);
      _secondaryTextColor(useDarkText, 0.6);
      final progressActive = _primaryTextColor(useDarkText);
      final progressInactive = _secondaryTextColor(useDarkText, 0.2);
      final timeColor = _secondaryTextColor(useDarkText, 0.55);
      const miniFontSize = 14.0;
      const miniLineGap = 6.0;
      const miniActiveScale = 1.12;

      return Column(
      children: [
        const Spacer(flex: 1),

        // 2. Artwork
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: vm.currentSong != null
                    ? ArtworkWidget(
                        song: vm.currentSong!,
                        size: 300,
                        borderRadius: 12,
                      )
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(
                          Icons.music_note,
                          size: 80,
                          color: Colors.white24,
                        ),
                      ),
              ),
            ),
          ),
        ),

        const Spacer(flex: 1),

        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTapLyrics,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              height: 84,
              child: hasLyrics
                  ? _MiniLyricsBlock(
                      lines: vm.lyricsLines,
                      currentIndex: vm.currentLyricIndex,
                      alignment: vm.miniLyricsAlignment,
                      inactiveColor: _secondaryTextColor(useDarkText, 0.55),
                      activeColor: _primaryTextColor(useDarkText),
                      fontSize: miniFontSize,
                      lineGap: miniLineGap,
                      activeScale: miniActiveScale,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '暂无歌词',
                            style: TextStyle(
                              color: _primaryTextColor(useDarkText),
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '纯音乐或未匹配到歌词',
                            style: TextStyle(
                              color: _secondaryTextColor(useDarkText, 0.5),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),

        const Spacer(flex: 2),

        // 4. Progress Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: progressActive,
                  inactiveTrackColor: progressInactive,
                  thumbColor: progressActive,
                ),
                child: Slider(
                  value: vm.duration.inMilliseconds > 0
                      ? (_isSeeking
                          ? _seekValue
                          : (vm.position.inMilliseconds /
                                  vm.duration.inMilliseconds)
                              .clamp(0.0, 1.0))
                      : 0.0,
                  onChangeStart: vm.duration.inMilliseconds > 0
                      ? (v) {
                          _isSeeking = true;
                          _seekValue = (vm.position.inMilliseconds /
                                  vm.duration.inMilliseconds)
                              .clamp(0.0, 1.0);
                        }
                      : null,
                  onChanged: vm.duration.inMilliseconds > 0
                      ? (v) {
                          setState(() {
                            _isSeeking = true;
                            _seekValue = v.clamp(0.0, 1.0);
                          });
                        }
                      : null,
                  onChangeEnd: vm.duration.inMilliseconds > 0
                      ? (v) {
                          final clamped = v.clamp(0.0, 1.0);
                          final target = Duration(
                            milliseconds:
                                (vm.duration.inMilliseconds * clamped).round(),
                          );
                          vm.seek(target);
                          setState(() {
                            _isSeeking = false;
                          });
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(vm.position),
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(vm.duration),
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 5. Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_previous_rounded, color: iconColor),
              onPressed: () => vm.previous(),
            ),
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _secondaryTextColor(useDarkText, 0.15),
              ),
              child: IconButton(
                iconSize: 64,
                icon: Icon(
                  vm.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: titleColor,
                ),
                onPressed: () => vm.isPlaying ? vm.pause() : vm.play(),
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 48,
              icon: Icon(Icons.skip_next_rounded, color: iconColor),
              onPressed: () => vm.next(),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // 6. Bottom Actions
        Padding(
          padding: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  vm.mode == PlaybackMode.shuffle
                      ? Icons.shuffle
                      : (vm.mode == PlaybackMode.loop ? Icons.repeat : Icons.repeat_one),
                  color: iconColor,
                ),
                onPressed: () => vm.cyclePlaybackMode(),
              ),
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.alarm,
                      color: iconColor,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => _SleepTimerSheet(
                          onSelect: (d) => vm.setSleepTimer(d),
                          onCancel: () => vm.cancelSleepTimer(),
                          onSongEnd: () => vm.setSleepTimerToSongEnd(),
                          isActive: vm.isSleepTimerActive,
                        ),
                      );
                    },
                  ),
                  if (vm.sleepTimerDisplayText != null)
                    Positioned(
                      bottom: -8,
                      child: Text(
                        vm.sleepTimerDisplayText!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: iconColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.format_list_bulleted, color: iconColor),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (c) => const PlaylistSheet(),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.more_horiz, color: iconColor),
                onPressed: () {
                  if (vm.currentSong != null) {
                    SongDetailSheet.show(context, vm.currentSong!);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
    },);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

}

class _MiniLyricsBlock extends StatelessWidget {
  final List<LyricLine> lines;
  final int currentIndex;
  final String alignment;
  final Color inactiveColor;
  final Color activeColor;
  final double fontSize;
  final double lineGap;
  final double activeScale;

  const _MiniLyricsBlock({
    required this.lines,
    required this.currentIndex,
    required this.alignment,
    required this.inactiveColor,
    required this.activeColor,
    required this.fontSize,
    required this.lineGap,
    required this.activeScale,
  });

  @override
  Widget build(BuildContext context) {
    final (prev, current, next) = _resolveLines();
    final textAlign = switch (alignment) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final crossAlign = switch (alignment) {
      'left' => CrossAxisAlignment.start,
      'right' => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };
    final blockAlign = switch (alignment) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };

    return Align(
      alignment: blockAlign,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAlign,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            prev,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: inactiveColor,
              fontSize: fontSize,
              height: 1.2,
            ),
          ),
          SizedBox(height: lineGap),
          Text(
            current,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: activeColor,
              fontSize: fontSize * activeScale,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          SizedBox(height: lineGap),
          Text(
            next,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: inactiveColor,
              fontSize: fontSize,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  (String, String, String) _resolveLines() {
    if (lines.isEmpty || currentIndex < 0 || currentIndex >= lines.length) {
      if (lines.isEmpty) {
        return ('', '', '');
      }
      final first = lines.first.text.trim();
      final second = lines.length > 1 ? lines[1].text.trim() : '';
      return ('', first, second);
    }
    final prevIndex = currentIndex - 1;
    final nextIndex = currentIndex + 1;
    final prev = prevIndex >= 0 ? lines[prevIndex].text.trim() : '';
    final current = lines[currentIndex].text.trim();
    final next = nextIndex < lines.length ? lines[nextIndex].text.trim() : '';
    return (prev, current, next);
  }
}

class PlaylistSheet extends StatefulWidget {
  const PlaylistSheet({super.key});

  @override
  State<PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<PlaylistSheet> {
  static const double _itemExtent = 60;
  late final ScrollController _controller;
  int _lastIndex = -1;

  double _calcOffset(int index, int length) {
    if (index <= 0 || length <= 0) return 0;
    final startIndex = (index - 2).clamp(0, length - 1);
    return startIndex * _itemExtent;
  }

  @override
  void initState() {
    super.initState();
    final vm = PlayerViewModel();
    _lastIndex = vm.currentIndex;
    _controller = ScrollController(
      initialScrollOffset: _calcOffset(_lastIndex, vm.queue.length),
    );
  }

  @override
  void didUpdateWidget(covariant PlaylistSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.playbackTick);
      watchSignal(context, vm.uiTick);
      final scheme = Theme.of(context).colorScheme;
      final playbackMode = vm.playbackThemeMode;
      final dominantColor = vm.dominantColor;
      final preferLightBackground = _preferLightBackground(context, playbackMode);
      final useDarkText = _useDarkText(dominantColor, preferLightBackground);
      final textColor = _primaryTextColor(useDarkText);
      final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
      final maskColor = preferLightBackground
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.28);
      final total = vm.queue.length;
      final current = vm.currentIndex >= 0 ? vm.currentIndex + 1 : 0;
      if (vm.currentIndex != _lastIndex && vm.currentIndex >= 0) {
        _lastIndex = vm.currentIndex;
        final offset = _calcOffset(_lastIndex, total);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_controller.hasClients) {
            _controller.animateTo(
              offset,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
      final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
      return _PlaylistSheetView(
        height: sheetHeight,
        maskColor: maskColor,
        dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
        header: _PlaylistHeader(
          total: total,
          current: current,
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
          onClear: () => vm.clearQueue(),
        ),
        list: _PlaylistQueueList(
          controller: _controller,
          itemExtent: _itemExtent,
          queue: vm.queue,
          currentIndex: vm.currentIndex,
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
          primaryColor: scheme.primary,
          onTap: (index) => vm.playSongInQueue(index),
          onDelete: (index) => vm.removeFromQueue(index),
          onReorder: (oldIndex, newIndex) =>
              vm.reorderQueue(oldIndex, newIndex),
        ),
      );
    },);
  }
}

class _PlaylistSheetView extends StatelessWidget {
  final double height;
  final Color maskColor;
  final Widget header;
  final Widget list;
  final Color dragHandleColor;

  const _PlaylistSheetView({
    required this.height,
    required this.maskColor,
    required this.header,
    required this.list,
    required this.dragHandleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Stack(
          children: [
            const RepaintBoundary(child: _PlayerBackground()),
            RepaintBoundary(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(color: maskColor),
              ),
            ),
            Column(
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 32,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: dragHandleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                header,
                list,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final int total;
  final int current;
  final Color textColor;
  final Color secondaryTextColor;
  final VoidCallback onClear;

  const _PlaylistHeader({
    required this.total,
    required this.current,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            height: 34,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 2,
                  child: Text(
                    '$current/$total',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    '播放队列',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 2,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerRight,
                    ),
                    onPressed: onClear,
                    child: Text(
                      '清空',
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}

class _PlaylistQueueList extends StatelessWidget {
  final ScrollController controller;
  final double itemExtent;
  final List<MusicEntity> queue;
  final int currentIndex;
  final Color textColor;
  final Color secondaryTextColor;
  final Color primaryColor;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onDelete;
  final void Function(int, int) onReorder;

  const _PlaylistQueueList({
    required this.controller,
    required this.itemExtent,
    required this.queue,
    required this.currentIndex,
    required this.textColor,
    required this.secondaryTextColor,
    required this.primaryColor,
    required this.onTap,
    required this.onDelete,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: RepaintBoundary(
        child: ReorderableListView.builder(
          scrollController: controller,
          itemExtent: itemExtent,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) {
                final double animValue = Curves.easeInOut.transform(animation.value);
                final double elevation = ui.lerpDouble(0, 6, animValue)!;
                return Material(
                  elevation: elevation,
                  color: Colors.transparent,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  child: child,
                );
              },
              child: child,
            );
          },
          onReorder: onReorder,
          itemCount: queue.length,
          itemBuilder: (context, index) {
            final song = queue[index];
            final isCurrent = index == currentIndex;
            final titleColor = isCurrent ? primaryColor : textColor;
            final artistColor = secondaryTextColor.withValues(alpha: 0.85);
            return RepaintBoundary(
              key: ValueKey(song.id),
              child: AppListTile(
                title: song.title,
                subtitle: song.artist,
                titleColor: titleColor,
                subtitleColor: artistColor,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: secondaryTextColor, size: 20),
                      onPressed: () => onDelete(index),
                    ),
                    ReorderableDelayedDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, right: 8),
                        child: Icon(Icons.menu, color: secondaryTextColor, size: 20),
                      ),
                    ),
                  ],
                ),
                onTap: () => onTap(index),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SleepTimerSheet extends StatefulWidget {
  final void Function(Duration duration) onSelect;
  final VoidCallback onCancel;
  final VoidCallback onSongEnd;
  final bool isActive;
  const _SleepTimerSheet({
    required this.onSelect,
    required this.onCancel,
    required this.onSongEnd,
    required this.isActive,
  });

  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  double _minutes = 30;

  @override
  void initState() {
    super.initState();
    final vm = PlayerViewModel();
    final remaining = vm.sleepRemaining;
    if (remaining != null && remaining > const Duration(minutes: 1)) {
      final m = remaining.inMinutes.clamp(5, 120);
      _minutes = m.toDouble();
    }
  }

  String _formatMinutes(num minutes) {
    final totalMinutes = minutes.round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '$hours:${mins.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.sleepTick);
      watchSignal(context, vm.playbackTick);
      watchSignal(context, vm.uiTick);
      final playbackMode = vm.playbackThemeMode;
      final dominantColor = vm.dominantColor;
      final preferLightBackground = _preferLightBackground(context, playbackMode);
      final useDarkText = _useDarkText(dominantColor, preferLightBackground);
      final textColor = _primaryTextColor(useDarkText);
      final secondaryTextColor = _secondaryTextColor(useDarkText, 0.7);
      final maskColor = preferLightBackground
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.28);
      final sheetHeight = MediaQuery.sizeOf(context).height * 0.4;
      return _PlaylistSheetView(
        height: sheetHeight,
        maskColor: maskColor,
        dragHandleColor: secondaryTextColor.withValues(alpha: 0.2),
        header: _SleepTimerHeader(
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
        ),
        list: Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                LabeledSlider(
                  title: '定时时长',
                  value: _minutes,
                  min: 5,
                  max: 120,
                  divisions: 23,
                  tickCount: 24,
                  valueText: _formatMinutes(_minutes),
                  label: '${_minutes.round()} 分钟',
                  onChanged: (v) {
                    setState(() {
                      _minutes = v;
                    });
                  },
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '播完整首歌后关闭',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: textColor,
                            ),
                      ),
                    ),
                    Switch.adaptive(
                      value: vm.sleepUntilSongEnd,
                      onChanged: (value) {
                        if (value) {
                          widget.onSongEnd();
                        } else {
                          widget.onCancel();
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onSelect(Duration(minutes: _minutes.round()));
                    },
                    child: const Text('开始定时'),
                  ),
                ),
                if (vm.isSleepTimerActive) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onCancel();
                      },
                      child: const Text('取消定时'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),);
    },);
    }
  }

class _SleepTimerHeader extends StatelessWidget {
  final Color textColor;
  final Color secondaryTextColor;

  const _SleepTimerHeader({
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            height: 34,
            child: Center(
              child: Text(
                '定时',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: secondaryTextColor.withValues(alpha: 0.18),
        ),
      ],
    );
  }
}
