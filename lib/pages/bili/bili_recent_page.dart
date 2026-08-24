import 'package:flutter/material.dart';

import '../../app/services/bili/bili_music_service.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_radii.dart';
import '../../components/index.dart';
import 'bili_playback.dart';

/// 完整的 B 站播放历史。B站主页「最近播放」右边的「查看更多」推进来。
class BiliRecentPage extends StatefulWidget {
  const BiliRecentPage({super.key});

  @override
  State<BiliRecentPage> createState() => _BiliRecentPageState();
}

class _BiliRecentPageState extends State<BiliRecentPage> {
  final BiliMusicService _music = BiliMusicService.instance;
  final PlayerService _player = PlayerService.instance;

  List<SongEntity> _songs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 历史页要看全，往前翻的记录数和取回条数都放宽。
    final songs = await _music.recentlyPlayed(limit: 200, scanLimit: 2000);
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '最近播放',
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(AppIcons.play),
              onPressed: () => _player.playQueue(_songs, 0),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
          ? Center(
              child: Text(
                '还没有 B 站的播放记录',
                style: TextStyle(color: AppColors.of(context).muted),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
                itemCount: _songs.length,
                itemBuilder: (context, index) => BiliSongRow(
                  song: _songs[index],
                  onTap: () => _player.playQueue(_songs, index),
                ),
              ),
            ),
    );
  }
}

/// B 站曲目的列表行，版式对齐首页的推荐歌曲行。
class BiliSongRow extends StatelessWidget {
  final SongEntity song;
  final VoidCallback onTap;

  const BiliSongRow({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: 66,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: Row(
            children: [
              ArtworkWidget(
                song: song,
                size: 52,
                borderRadius: AppRadii.chip,
                placeholder: LetterArtworkPlaceholder(
                  size: 52,
                  fontWeight: FontWeight.w700,
                  label: song.title.isEmpty ? '?' : song.title[0],
                ),
              ),
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
                      song.album ?? song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatBiliDuration((song.durationMs ?? 0) ~/ 1000),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
