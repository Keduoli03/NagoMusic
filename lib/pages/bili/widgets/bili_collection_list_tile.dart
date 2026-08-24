import 'package:flutter/material.dart';

import '../../../app/services/bili/bili_collection_service.dart';
import '../../../app/services/bili/bili_music_service.dart';
import '../../../app/theme/tokens.dart';
import '../bili_playback.dart';
import 'bili_cover_image.dart';

/// 仿 B 站历史记录的信息结构：封面进度 + 标题 + 当前分 P + UP 主。
class BiliCollectionListTile extends StatelessWidget {
  static const double _coverWidth = 120;
  static const double _coverHeight = 68;

  final BiliVideoCollection collection;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const BiliCollectionListTile({
    super.key,
    required this.collection,
    required this.onTap,
    this.onLongPress,
  });

  String get _partLabel {
    final parts = collection.detail.parts;
    if (!collection.hasProgress) {
      return parts.length == 1 ? '单 P' : '共 ${parts.length} 个分 P';
    }
    final part = parts[collection.resumeIndex];
    return BiliMusicService.partLabel(collection.video.title, part);
  }

  String get _progressLabel {
    final currentSeconds = collection.hasProgress
        ? collection.resumePosition.inSeconds
        : 0;
    final videoDuration = collection.video.durationSec;
    final fallbackDuration = collection.detail.parts.fold<int>(
      0,
      (total, part) => total + part.durationSec,
    );
    final totalSeconds = videoDuration > 0 ? videoDuration : fallbackDuration;
    final current = currentSeconds <= 0
        ? '0:00'
        : formatBiliDuration(currentSeconds);
    if (totalSeconds <= 0) return current;
    return '$current / ${formatBiliDuration(totalSeconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final video = collection.video;
    final author = video.author.isEmpty ? '哔哩哔哩' : video.author;

    return Semantics(
      button: true,
      label: '${video.title}，$_partLabel，$author，播放进度 $_progressLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.rCard,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: AppSpacing.cardTight.copyWith(
              left: 0,
              right: 0,
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCover(context),
                AppSpacing.wGapMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLg.on(colors.text),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        _partLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.meta.on(colors.text),
                      ),
                      AppSpacing.gapSm,
                      Row(
                        children: [
                          Icon(
                            AppIcons.person,
                            size: AppSpacing.lg,
                            color: colors.muted,
                          ),
                          AppSpacing.wGapXs,
                          Expanded(
                            child: Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.on(colors.muted),
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
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final video = collection.video;

    return ClipRRect(
      borderRadius: AppRadii.rCard,
      child: SizedBox(
        width: _coverWidth,
        height: _coverHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BiliCoverImage(video: video),
            Positioned(
              right: AppSpacing.xs,
              bottom: AppSpacing.xs,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.dark.bg.withValues(alpha: 0.72),
                  borderRadius: AppRadii.rBadge,
                ),
                child: Padding(
                  padding: AppSpacing.cardTight.copyWith(
                    left: AppSpacing.xs,
                    right: AppSpacing.xs,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    _progressLabel,
                    style: AppTypography.badge.on(AppColors.dark.text),
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
