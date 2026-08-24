import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/state/song_state.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radii.dart';
import '../../../components/index.dart';

class HomeRecommendationSection extends StatefulWidget {
  final List<SongEntity> songs;
  final VoidCallback onPlayAll;
  final ValueChanged<SongEntity> onTapSong;

  const HomeRecommendationSection({
    super.key,
    required this.songs,
    required this.onPlayAll,
    required this.onTapSong,
  });

  @override
  State<HomeRecommendationSection> createState() =>
      _HomeRecommendationSectionState();
}

class _HomeRecommendationSectionState
    extends State<HomeRecommendationSection> {
  final PageController _pageController = PageController();

  @override
  void didUpdateWidget(covariant HomeRecommendationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.songs.map((song) => song.id).join('|');
    final newIds = widget.songs.map((song) => song.id).join('|');
    if (oldIds != newIds && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '根据你喜欢的歌曲推荐',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            SoftIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: '播放全部',
              onTap: widget.onPlayAll,
              size: 34,
              iconSize: 21,
              radius: AppRadii.card,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.songs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.panel),
            ),
            child: Text(
              '收藏几首喜欢的歌后，这里会出现更贴合你的推荐',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 198,
            child: PageView.builder(
              controller: _pageController,
              itemCount: (widget.songs.length + 2) ~/ 3,
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * 3;
                final end = min(start + 3, widget.songs.length);
                return Column(
                  children: widget.songs
                      .sublist(start, end)
                      .map(
                        (song) => RecommendationSongTile(
                          song: song,
                          onTap: () => widget.onTapSong(song),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
      ],
    );
  }
}

class RecommendationSongTile extends StatelessWidget {
  final SongEntity song;
  final VoidCallback onTap;

  const RecommendationSongTile({
    super.key,
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Row(
          children: [
            ArtworkWidget(song: song, size: 52, borderRadius: AppRadii.chip),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            // 原来这里是一个孤零零的黑色 ▶ 图标，看不出是控件也不像卡片语言。
            SoftIconButton(
              icon: Icons.play_arrow_rounded,
              onTap: onTap,
              size: 28,
              iconSize: 17,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
