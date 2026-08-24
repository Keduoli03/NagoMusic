import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';

import '../../../app/services/bili/bili_music_service.dart';
import '../../../app/theme/tokens.dart';

/// 优先显示磁盘缓存的 B 站视频封面，网络封面只作为缓存尚未就绪时的回退。
class BiliCoverImage extends StatefulWidget {
  final BiliVideo video;
  final BoxFit fit;

  const BiliCoverImage({
    super.key,
    required this.video,
    this.fit = BoxFit.cover,
  });

  @override
  State<BiliCoverImage> createState() => _BiliCoverImageState();
}

class _BiliCoverImageState extends State<BiliCoverImage> {
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    _resolveCover();
  }

  @override
  void didUpdateWidget(covariant BiliCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.bvid != widget.video.bvid ||
        oldWidget.video.cover != widget.video.cover) {
      _cachedPath = null;
      _resolveCover();
    }
  }

  Future<void> _resolveCover() async {
    final path = await BiliMusicService.instance.cacheVideoCover(
      widget.video.bvid,
      widget.video.cover,
    );
    if (!mounted || path == null) return;
    setState(() => _cachedPath = path);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: AppColors.of(context).mediaBg);
    final cachedPath = _cachedPath;
    if (cachedPath != null) {
      return Image.file(
        File(cachedPath),
        fit: widget.fit,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) =>
            _networkOrPlaceholder(placeholder),
      );
    }
    return _networkOrPlaceholder(placeholder);
  }

  Widget _networkOrPlaceholder(Widget placeholder) {
    final cover = widget.video.cover.trim();
    if (cover.isEmpty) return placeholder;
    return Image.network(
      cover,
      fit: widget.fit,
      gaplessPlayback: true,
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
