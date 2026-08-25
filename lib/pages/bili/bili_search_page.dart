import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../components/index.dart';
import 'bili_playback.dart';
import 'controllers/bili_search_controller.dart';

/// B 站搜索页。
///
/// 从 B站主页右上角的搜索按钮推进来 —— 搜索是低频动作，不值得在主页常驻一个
/// 输入框和一个分段切换器。
///
/// 翻页状态全在 [BiliSearchController] 里，这里只负责「滚到底就喊一声」和把
/// 状态画出来。
class BiliSearchPage extends StatefulWidget {
  const BiliSearchPage({super.key});

  @override
  State<BiliSearchPage> createState() => _BiliSearchPageState();
}

class _BiliSearchPageState extends State<BiliSearchPage> {
  final BiliApi _api = BiliApi.instance;
  final TextEditingController _keyword = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  late final BiliSearchController _search = BiliSearchController(
    search: (keyword, page) => _api.searchVideos(keyword, page: page),
  );

  /// 距底还有多少像素就开始预加载。留一屏左右，滚到底时下一页通常已经到了。
  static const double _loadMoreThreshold = 600;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    _keyword.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      // loadMore 内部自己挡并发、到底、以及「上一页刚失败」的情况，
      // 所以这里可以无脑调，不用在滚动回调里再判一遍。
      _search.loadMore();
    }
  }

  void _submit() {
    _focus.unfocus();
    _search.submit(_keyword.text);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // 搜索框搬进顶栏后不再需要 extendBodyBehindAppBar：内容直接从顶栏下面
      // 开始，背景由外层 AppBackground 铺满。
      resizeToAvoidBottomInset: false,
      appBar: AppTopBar(
        titleWidget: AppSearchField(
          controller: _keyword,
          focusNode: _focus,
          autofocus: true,
          hintText: '搜索 B 站视频音频',
          onSubmitted: (_) => _submit(),
        ),
        titleSpacing: 0,
        actions: [
          TextButton(
            onPressed: _submit,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: AppSpacing.hMd,
            ),
            child: Text(
              '搜索',
              style: AppTypography.bodyLg.on(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: _search,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_search.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.error.isNotEmpty) {
      return _hint(_search.error, actionLabel: '重试', onAction: _submit);
    }
    if (_search.isEmpty) {
      return _hint(
        _search.keyword.isEmpty
            ? '输入关键词，搜索 B 站上的音频'
            : '没有搜到「${_search.keyword}」相关内容',
      );
    }

    final results = _search.results;
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        bottomPadding,
      ),
      // 多一格给底部状态（加载中 / 到底了 / 加载失败）。
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == results.length) return _buildFooter(context);
        final video = results[index];
        return BiliVideoTile(
          video: video,
          onTap: () => BiliPlayback.openVideo(context, video),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final c = AppColors.of(context);

    if (_search.moreError.isNotEmpty) {
      // 翻页失败不清空已有结果，只在底部提示 + 给个重试。
      return Padding(
        padding: AppSpacing.card,
        child: Column(
          children: [
            Text(
              _search.moreError,
              textAlign: TextAlign.center,
              style: AppTypography.caption.on(c.muted),
            ),
            AppSpacing.gapSm,
            FilledButton.tonal(
              onPressed: _search.retryMore,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_search.isLoadingMore) {
      return const Padding(
        padding: AppSpacing.card,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_search.hasMore) {
      return Padding(
        padding: AppSpacing.card,
        child: Center(
          child: Text('没有更多了', style: AppTypography.caption.on(c.muted)),
        ),
      );
    }

    // 还有下一页但还没触发加载（比如首屏没铺满）——占位即可，滚动回调会接手。
    return AppSpacing.gapXl;
  }

  Widget _hint(String message, {String? actionLabel, VoidCallback? onAction}) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.on(c.muted),
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
