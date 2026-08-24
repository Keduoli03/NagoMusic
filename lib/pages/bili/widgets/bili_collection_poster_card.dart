import 'package:flutter/material.dart';

import '../../../app/services/bili/bili_collection_service.dart';
import '../../../app/theme/tokens.dart';

/// 首页「每日推荐」同规格的 B 站收藏海报。
class BiliCollectionPosterCard extends StatelessWidget {
  static const double width = 120;
  static const double _coverSize = 120;
  static const double _footerHeight = 38;
  static const double height = _coverSize + _footerHeight;

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
    final scheme = Theme.of(context).colorScheme;
    final overlayText = AppColors.dark.text;
    final footerColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.18),
      AppColors.dark.surface,
    );

    return Semantics(
      button: true,
      label: '播放收藏视频：${video.title}',
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.rCard,
            child: ClipRRect(
              borderRadius: AppRadii.rCard,
              child: Column(
                children: [
                  SizedBox(
                    width: _coverSize,
                    height: _coverSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCover(context),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.dark.bg.withValues(alpha: 0.68),
                                AppColors.dark.bg.withValues(alpha: 0),
                                AppColors.dark.bg.withValues(alpha: 0.18),
                              ],
                              stops: const [0, 0.48, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: AppSpacing.sm,
                          top: AppSpacing.sm,
                          right: AppSpacing.sm,
                          child: Row(
                            children: [
                              Icon(
                                AppIcons.bookmark,
                                color: overlayText,
                                size: AppSpacing.lg,
                              ),
                              AppSpacing.wGapXs,
                              Expanded(
                                child: Text(
                                  video.author.isEmpty ? '哔哩哔哩' : video.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.meta.strong.on(
                                    overlayText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: AppSpacing.sm,
                          bottom: AppSpacing.sm,
                          child: Icon(
                            AppIcons.play,
                            color: overlayText,
                            size: AppSpacing.xl,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: width,
                    height: _footerHeight,
                    padding: AppSpacing.cardTight.copyWith(top: 0, bottom: 0),
                    color: footerColor,
                    alignment: Alignment.center,
                    child: Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.micro.strong.on(overlayText),
                    ),
                  ),
                ],
              ),
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
