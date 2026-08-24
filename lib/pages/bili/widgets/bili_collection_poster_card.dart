import 'package:flutter/material.dart';

import '../../../app/services/bili/bili_collection_service.dart';
import '../../../app/theme/tokens.dart';

/// 首页「每日推荐」同规格的 B 站收藏海报。
class BiliCollectionPosterCard extends StatelessWidget {
  static const double width = 176;
  static const double _coverHeight = 99;
  static const double _footerHeight = 76;
  static const double height = _coverHeight + _footerHeight;

  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extraScale = (scale - 1).clamp(0, 2);
    return height + AppSpacing.xxl * 2 * extraScale;
  }

  final BiliVideoCollection collection;
  final VoidCallback onTap;

  const BiliCollectionPosterCard({
    super.key,
    required this.collection,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final video = collection.video;
    final colors = AppColors.of(context);
    final overlayText = AppColors.dark.text;
    final footerHeight = heightFor(context) - _coverHeight;
    final partLabel = collection.detail.parts.length == 1
        ? '单 P'
        : '${collection.detail.parts.length} 个分 P';
    final author = video.author.isEmpty ? '哔哩哔哩' : video.author;

    return Semantics(
      button: true,
      label: '播放收藏视频：${video.title}',
      child: SizedBox(
        width: width,
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.rCard,
            side: BorderSide(color: colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.rCard,
            child: Column(
              children: [
                SizedBox(
                  width: width,
                  height: _coverHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCover(context),
                      Positioned(
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.dark.bg.withValues(alpha: 0.62),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: AppSpacing.cardTight,
                            child: Icon(
                              AppIcons.play,
                              color: overlayText,
                              size: AppSpacing.lg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: width,
                  height: footerHeight,
                  padding: AppSpacing.cardTight.copyWith(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLg.on(colors.text),
                      ),
                      const Spacer(),
                      Text(
                        '$author · $partLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.on(colors.muted),
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
    final placeholder = ColoredBox(color: AppColors.of(context).mediaBg);
    if (video.cover.isEmpty) return placeholder;
    return Image.network(
      video.cover,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      headers: const {
        'Referer': 'https://www.bilibili.com',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/122.0.0.0 Safari/537.36',
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
