import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/bili/bili_api.dart';
import '../../app/services/bili/bili_models.dart';
import '../../app/services/bili/bili_music_service.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../components/index.dart';

/// 时长文本。
///
/// B 站上一部有声书合集动辄几百小时，只按「分:秒」格式化会得到 `831:05` 这种
/// 读不出来的数字，所以超过一小时就带上小时位。
String formatBiliDuration(int seconds) {
  if (seconds <= 0) return '';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final ss = rest.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// 「点一个 B 站视频 → 播起来」这条链路。
///
/// B站主页和搜索页都要走同一套（解析分 P、落库、缓存封面、进播放队列），
/// 抽出来避免两边各写一份。
class BiliPlayback {
  const BiliPlayback._();

  /// 点一条视频：单 P 直接播，多 P 弹分 P 列表。
  static Future<void> openVideo(BuildContext context, BiliVideo video) async {
    final music = BiliMusicService.instance;
    final closeProgress = _showProgress(context, '正在解析…');
    BiliVideoDetail detail;
    try {
      detail = await BiliApi.instance.videoDetail(video.bvid);
    } catch (e) {
      closeProgress();
      if (context.mounted) {
        AppToast.show(context, '解析失败：$e', type: ToastType.error);
      }
      return;
    }
    closeProgress();
    if (!context.mounted) return;

    final songs = music.songsFromDetail(detail);
    if (songs.isEmpty) {
      AppToast.show(context, '这个视频没有可播放的音频', type: ToastType.error);
      return;
    }
    if (songs.length == 1) {
      await playSongs(songs, 0, video.cover);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 合集动辄几十上百个分 P，必须给面板封顶高度并让内部自己滚动，
      // 否则 AppSheetPanel 的 Column 会给列表无限高度约束，直接撑爆。
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      builder: (sheetContext) => BiliPartPickerSheet(
        detail: detail,
        onPlayAll: () {
          Navigator.pop(sheetContext);
          playSongs(songs, 0, video.cover);
        },
        onPlayPart: (index) {
          Navigator.pop(sheetContext);
          playSongs(songs, index, video.cover);
        },
      ),
    );
  }

  static Future<void> playSongs(
    List<SongEntity> songs,
    int index,
    String coverUrl,
  ) async {
    final music = BiliMusicService.instance;
    // 封面下载不阻塞播放：先落库开播，封面回来了再补一次。
    await music.persist(songs);
    unawaited(_cacheCovers(songs, coverUrl));
    await PlayerService.instance.playQueue(songs, index);
  }

  static Future<void> _cacheCovers(
    List<SongEntity> songs,
    String coverUrl,
  ) async {
    if (coverUrl.isEmpty) return;
    final music = BiliMusicService.instance;
    final withCover = <SongEntity>[];
    for (final song in songs) {
      final updated = await music.cacheCover(song, coverUrl);
      if (updated.localCoverPath != null) withCover.add(updated);
    }
    await music.persist(withCover);
  }

  /// 显示一个不可取消的等待遮罩，返回关掉它的回调。
  static VoidCallback _showProgress(BuildContext context, String message) {
    var closed = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    return () {
      if (closed || !context.mounted) return;
      closed = true;
      Navigator.of(context, rootNavigator: true).pop();
    };
  }
}

/// 搜索结果里的一条视频。
///
/// 不用 [MediaListTile]：那一套底层的 [AppListTile] 把标题写死成单行，而 B 站的
/// 标题普遍很长（「有声小说《三体》（读客熊猫君）第一部 纯享版 高音质」），
/// 单行截断之后几乎看不出是哪个版本。这里给两行标题和 16:9 的封面。
class BiliVideoTile extends StatelessWidget {
  final BiliVideo video;
  final VoidCallback onTap;

  const BiliVideoTile({super.key, required this.video, required this.onTap});

  static const double _coverWidth = 104;
  static const double _coverHeight = 65;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final duration = formatBiliDuration(video.durationSec);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(context, duration),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 13,
                          color: c.muted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            video.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, String duration) {
    final placeholder = Container(
      width: _coverWidth,
      height: _coverHeight,
      color: Theme.of(context).cardColor,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: SizedBox(
        width: _coverWidth,
        height: _coverHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video.cover.isEmpty)
              placeholder
            else
              Image.network(
                video.cover,
                fit: BoxFit.cover,
                // hdslb 的图床对空 Referer 会返回 403。
                headers: const {
                  'Referer': 'https://www.bilibili.com',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/122.0.0.0 Safari/537.36',
                },
                errorBuilder: (context, error, stack) => placeholder,
              ),
            if (duration.isNotEmpty)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(AppRadii.badge),
                  ),
                  child: Text(
                    duration,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 多 P 视频的分 P 选择面板。
///
/// 独立成一个组件是为了能单独测：这里踩过一次 `AppSheetPanel` 非 expand 分支
/// 给子组件无限高度约束、57 个分 P 直接撑出 2289px 溢出的坑。面板高度由调用方
/// 通过 `showModalBottomSheet` 的 constraints 封顶，列表在 [Expanded] 里自己滚。
class BiliPartPickerSheet extends StatelessWidget {
  final BiliVideoDetail detail;
  final VoidCallback onPlayAll;
  final ValueChanged<int> onPlayPart;

  const BiliPartPickerSheet({
    super.key,
    required this.detail,
    required this.onPlayAll,
    required this.onPlayPart,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).muted;
    final videoTitle = detail.video.title;
    final parts = detail.parts;
    return AppSheetPanel(
      title: '选择分 P',
      expand: true,
      // AppSheetPanel 的外壳是 DecoratedBox 不是 Material，直接放 ListTile 会
      // 断言「涟漪不可见」。补一层透明 Material 让水波有地方画。
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                videoTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: Text('播放全部 ${parts.length} 个分 P'),
              onTap: onPlayAll,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: parts.length,
                itemBuilder: (context, index) {
                  final part = parts[index];
                  final label = BiliMusicService.partLabel(videoTitle, part);
                  // 分 P 没有独立名字时 partLabel 已经回退成 "P3"，此时再画一列
                  // 索引就成了「P3　P3」，所以那种情况不要 leading。
                  final redundant = label == 'P${part.index}';
                  return ListTile(
                    dense: true,
                    leading: redundant
                        ? null
                        : SizedBox(
                            width: 36,
                            child: Text(
                              'P${part.index}',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                    title: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      formatBiliDuration(part.durationSec),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    onTap: () => onPlayPart(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
