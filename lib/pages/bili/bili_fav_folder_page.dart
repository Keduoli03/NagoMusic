import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';

import '../../app/services/log/log.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../components/index.dart';
import 'bili_playback.dart';

typedef BiliFavResourcesLoader = Future<List<BiliVideo>> Function(int folderId);
typedef BiliVideoOpener =
    Future<void> Function(BuildContext context, BiliVideo video);

/// B 站账号内一个远程收藏夹的视频列表。
class BiliFavFolderPage extends StatefulWidget {
  final BiliFavFolder folder;
  final BiliFavResourcesLoader? loadResources;
  final BiliVideoOpener? openVideo;

  const BiliFavFolderPage({
    super.key,
    required this.folder,
    this.loadResources,
    this.openVideo,
  });

  @override
  State<BiliFavFolderPage> createState() => _BiliFavFolderPageState();
}

class _BiliFavFolderPageState extends State<BiliFavFolderPage> {
  static const String _logTag = 'BiliFavFolderPage';

  List<BiliVideo> _videos = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final loader = widget.loadResources ?? BiliApi.instance.favResources;
      final videos = await loader(widget.folder.id);
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _loading = false;
      });
    } catch (e, s) {
      AppLog.instance.w(
        _logTag,
        '加载收藏夹视频失败，folderId=${widget.folder.id}',
        e,
        s,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is BiliApiException ? e.message : '加载失败：$e';
      });
    }
  }

  Future<void> _open(BiliVideo video) async {
    final opener = widget.openVideo ?? BiliPlayback.openVideo;
    await opener(context, video);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.folder.title,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? _message(_error, actionLabel: '重试', onAction: _load)
          : _videos.isEmpty
          ? _message('这个收藏夹还没有可播放的视频')
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: AppSpacing.page.copyWith(
                  top: AppSpacing.sm,
                  bottom: bottomPadding,
                ),
                itemCount: _videos.length,
                itemBuilder: (context, index) {
                  final video = _videos[index];
                  return BiliVideoTile(video: video, onTap: () => _open(video));
                },
              ),
            ),
    );
  }

  Widget _message(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.on(AppColors.of(context).muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.gapLg,
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
