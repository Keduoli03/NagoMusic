import 'package:flutter/material.dart';

import '../../../app/services/bili/bili_music_service.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/song_state.dart';
import '../../../app/theme/tokens.dart';
import '../../../components/common/playing_bars.dart';

/// 与首页一致：当前播放的 B 站合集显示动态音柱，暂停时保留静态音柱。
class BiliCollectionPlaybackIndicator extends StatelessWidget {
  final String bvid;
  final Color color;
  final double iconSize;

  const BiliCollectionPlaybackIndicator({
    super.key,
    required this.bvid,
    required this.color,
    required this.iconSize,
  });

  static bool matchesCollection(SongEntity? song, String bvid) {
    if (song == null || !BiliMusicService.isBiliSong(song)) return false;
    return BiliMusicService.parseSongId(song.id)?.$1 == bvid;
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: player.currentSong,
      builder: (context, song, _) {
        if (!matchesCollection(song, bvid)) {
          return Icon(AppIcons.play, color: color, size: iconSize);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: player.isPlaying,
          builder: (context, isPlaying, _) =>
              PlayingBars(color: color, animating: isPlaying),
        );
      },
    );
  }
}
