import 'package:bili_api/bili_api.dart';
import 'package:flutter/foundation.dart';

import '../../../app/services/log/log.dart';

/// B 站搜索的翻页状态机。
///
/// 从页面里抽出来是为了能测。翻页最容易错的三件事——**重复条目**、**什么时候算
/// 到底**、**并发触发**——都不需要真发网络请求、也不需要滚一个 ListView 才能验证，
/// 放在这里用假的 [search] 回调就能覆盖全。
///
/// 关于去重：B 站搜索接口相邻页之间会返回重复的 bvid（尤其是发起新搜索后排序
/// 抖动的时候），不去重的话列表里会出现同一个视频两次，而且 Flutter 的 key
/// 冲突会更难查。
class BiliSearchController extends ChangeNotifier {
  BiliSearchController({
    required this.search,
    this.pageSize = BiliApi.searchPageSize,
  });

  /// 取某一页。抽成回调而不是直接调 [BiliApi]，测试才好塞假数据。
  final Future<List<BiliVideo>> Function(String keyword, int page) search;

  /// 每页条数。用来判断「返回条数 < pageSize 就是最后一页」。
  final int pageSize;

  static const String _logTag = 'BiliSearch';

  final List<BiliVideo> _items = <BiliVideo>[];
  final Set<String> _seen = <String>{};

  String _keyword = '';
  int _page = 0;
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _error = '';
  String _moreError = '';

  /// 用来丢弃过期响应：用户改了关键词又搜一次时，上一次的请求回来了不能再写进去。
  int _token = 0;

  List<BiliVideo> get results => List<BiliVideo>.unmodifiable(_items);

  /// 首屏搜索中（整页转圈）。
  bool get isSearching => _searching;

  /// 加载下一页中（列表底部转圈）。
  bool get isLoadingMore => _loadingMore;

  /// 还有下一页。到底了、或者从没搜过时为 false。
  bool get hasMore => _hasMore;

  /// 首屏搜索的错误。
  String get error => _error;

  /// 加载下一页的错误。和 [error] 分开：翻页失败不该把已经搜到的结果清掉，
  /// 只在列表底部提示 + 给个重试。
  String get moreError => _moreError;

  String get keyword => _keyword;

  bool get isEmpty => _items.isEmpty;

  /// 发起一次新搜索，重置所有翻页状态。
  Future<void> submit(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final token = ++_token;
    _keyword = trimmed;
    _searching = true;
    _loadingMore = false;
    _error = '';
    _moreError = '';
    _items.clear();
    _seen.clear();
    _page = 0;
    _hasMore = false;
    notifyListeners();

    try {
      final page = await search(trimmed, 1);
      if (token != _token) return;
      _page = 1;
      _absorb(page);
      _hasMore = page.length >= pageSize;
      _searching = false;
      notifyListeners();
    } catch (e, s) {
      AppLog.instance.w(_logTag, '搜索B站视频失败 keyword=$trimmed', e, s);
      if (token != _token) return;
      _searching = false;
      _error = _messageOf(e);
      notifyListeners();
    }
  }

  /// 触底加载下一页。
  ///
  /// 重复调用是安全的：正在加载、已经到底、还没搜过、或者上一页刚失败过（要等
  /// 用户点重试）时直接返回，所以滚动回调里可以无脑调。
  Future<void> loadMore() async {
    if (_searching || _loadingMore || !_hasMore) return;
    if (_keyword.isEmpty) return;
    if (_moreError.isNotEmpty) return;

    final token = _token;
    _loadingMore = true;
    notifyListeners();

    try {
      final next = _page + 1;
      final page = await search(_keyword, next);
      if (token != _token) return;
      _page = next;
      final added = _absorb(page);
      // 判定「到底了」看的是**接口返回的条数**，不是去重后新增的条数：
      // 整页都是重复项时仍然可能有下一页，用新增数判断会提前停住。
      _hasMore = page.length >= pageSize;
      // 但整页一条新的都没有时还是得停，否则会对着同一页无限翻。
      if (added == 0) _hasMore = false;
      _loadingMore = false;
      notifyListeners();
    } catch (e, s) {
      AppLog.instance.w(
        _logTag,
        '加载B站搜索下一页失败 keyword=$_keyword page=${_page + 1}',
        e,
        s,
      );
      if (token != _token) return;
      _loadingMore = false;
      _moreError = _messageOf(e);
      notifyListeners();
    }
  }

  /// 翻页失败后重试同一页。
  Future<void> retryMore() async {
    if (_moreError.isEmpty) return;
    _moreError = '';
    notifyListeners();
    await loadMore();
  }

  /// 写入新一页，返回真正新增的条数（已去重）。
  int _absorb(List<BiliVideo> page) {
    var added = 0;
    for (final video in page) {
      if (video.bvid.isEmpty) continue;
      if (!_seen.add(video.bvid)) continue;
      _items.add(video);
      added++;
    }
    return added;
  }

  String _messageOf(Object e) => e is BiliApiException ? e.message : '搜索失败：$e';
}
