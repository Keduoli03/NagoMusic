import 'package:flutter/material.dart';

import '../../app/services/bili/bili_collection_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../components/index.dart';
import 'bili_playback.dart';

/// 用户保存在 NagoMusic 内的 B 站视频合集。
class BiliCollectionsPage extends StatefulWidget {
  const BiliCollectionsPage({super.key});

  @override
  State<BiliCollectionsPage> createState() => _BiliCollectionsPageState();
}

class _BiliCollectionsPageState extends State<BiliCollectionsPage> {
  final BiliCollectionService _collections = BiliCollectionService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _collections.ensureLoaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(BiliVideoCollection collection) async {
    await _collections.remove(collection.video.bvid);
    if (!mounted) return;
    AppToast.show(context, '已取消收藏「${collection.video.title}」');
  }

  String _subtitle(BiliVideoCollection collection) {
    final parts = collection.detail.parts;
    final countLabel = parts.length == 1 ? '单 P' : '${parts.length} 个分 P';
    if (!collection.hasProgress) {
      return '${collection.video.author} · $countLabel';
    }
    final part = parts[collection.resumeIndex];
    final position = formatBiliDuration(collection.resumePosition.inSeconds);
    final progress = position.isEmpty
        ? 'P${part.index}'
        : 'P${part.index} $position';
    return '${collection.video.author} · $countLabel · 上次 $progress';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '视频收藏',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<List<BiliVideoCollection>>(
              valueListenable: _collections.collections,
              builder: (context, collections, _) {
                if (collections.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: AppSpacing.card,
                      child: Text(
                        '还没有收藏视频合集\n在 B 站搜索结果中点击收藏按钮即可添加',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.on(
                          AppColors.of(context).muted,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: AppSpacing.page.copyWith(bottom: bottomPadding),
                  itemCount: collections.length,
                  itemBuilder: (context, index) {
                    final collection = collections[index];
                    return BiliVideoTile(
                      video: collection.video,
                      subtitle: _subtitle(collection),
                      onTap: () =>
                          BiliPlayback.openCollection(context, collection),
                      trailing: IconButton(
                        tooltip: '取消视频收藏',
                        icon: const Icon(AppIcons.bookmark),
                        onPressed: () => _remove(collection),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
