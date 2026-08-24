import 'package:flutter/material.dart';

import '../../../app/state/song_state.dart';
import '../../../app/theme/app_radii.dart';
import '../../../components/index.dart';

class DiscoveryCard extends StatelessWidget {
  static const double width = 120;
  static const double _coverSize = 120;
  static const double _footerHeight = 38;
  static const double height = _coverSize + _footerHeight;

  final String eyebrow;
  final String title;
  final IconData? icon;
  final SongEntity? song;
  final Color accent;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  const DiscoveryCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.song,
    required this.accent,
    required this.active,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentSong = song;
    final footerColor = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      const Color(0xFF211B1B),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Column(
              children: [
                SizedBox(
                  width: _coverSize,
                  height: _coverSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (currentSong != null)
                        // 这里刻意**不用** preferOriginal。卡片只有 120 逻辑像素，
                        // 3x 屏也就需要 360px，而磁盘缓存里的封面是 1024px，绰绰有余。
                        // preferOriginal 会绕开缓存、在 UI isolate 上同步解析音频标签
                        // 取出 1~3MB 的内嵌大图 —— 切换筛选时三张卡连着做三次，
                        // 这是首页最贵的一笔开销，而且在这个尺寸上肉眼看不出差别。
                        //
                        // keepPreviousUntilLoaded：换歌时先留着旧封面，别先闪成空白。
                        ArtworkWidget(
                          song: currentSong,
                          size: _coverSize,
                          borderRadius: 0,
                          keepPreviousUntilLoaded: true,
                        )
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.95),
                                accent.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x59000000),
                              Color(0x00000000),
                              Color(0x26000000),
                            ],
                            stops: [0, 0.48, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        right: 7,
                        child: Row(
                          children: [
                            if (icon == Icons.calendar_month_rounded)
                              const DiscoveryCalendarBadge()
                            else if (icon != null)
                              Icon(icon, color: Colors.white, size: 17),
                            if (icon != null) const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                eyebrow,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x8A000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 6,
                        child: active
                            ? PlayingBars(
                                color: Colors.white,
                                animating: playing,
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                                shadows: [
                                  Shadow(
                                    color: Color(0x8F000000),
                                    blurRadius: 5,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: width,
                  height: _footerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  color: footerColor,
                  alignment: Alignment.center,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DiscoveryCalendarBadge extends StatelessWidget {
  const DiscoveryCalendarBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 1.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Text(
                    '${DateTime.now().day}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(left: 4, top: 0, child: CalendarBinding()),
          const Positioned(right: 4, top: 0, child: CalendarBinding()),
        ],
      ),
    );
  }
}

class CalendarBinding extends StatelessWidget {
  const CalendarBinding({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
      ),
      child: const SizedBox(width: 1.5, height: 4),
    );
  }
}
