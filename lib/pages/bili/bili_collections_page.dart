import 'package:flutter/material.dart';

import '../../app/services/bili/bili_collection_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../components/index.dart';
import 'bili_playback.dart';
import 'widgets/bili_collection_list_tile.dart';

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
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '取消收藏',
      content: '确定不再收藏「${collection.video.title}」吗？',
      confirmText: '取消收藏',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _collections.remove(collection.video.bvid);
    if (!mounted) return;
    AppToast.show(context, '已取消收藏');
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '收藏的视频',
        leadingWidth: AppSpacing.xl * 2,
        titleSpacing: AppSpacing.xs,
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
                        '还没有收藏的视频\n在 B 站搜索结果中点击收藏按钮即可添加',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.on(
                          AppColors.of(context).muted,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: AppSpacing.page.copyWith(bottom: bottomPadding),
                  itemCount: collections.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final collection = collections[index];
                    return BiliCollectionListTile(
                      key: ValueKey(collection.video.bvid),
                      collection: collection,
                      onTap: () =>
                          BiliPlayback.openCollection(context, collection),
                      onLongPress: () => _remove(collection),
                    );
                  },
                );
              },
            ),
    );
  }
}
