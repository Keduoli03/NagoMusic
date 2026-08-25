import 'dart:async';

import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nagomusic/pages/bili/controllers/bili_search_controller.dart';

BiliVideo _video(String bvid) =>
    BiliVideo(bvid: bvid, aid: 0, title: bvid, author: 'a', cover: '');

List<BiliVideo> _page(List<String> bvids) => bvids.map(_video).toList();

void main() {
  // 用 3 当每页条数，测试数据不用堆 30 条。
  const size = 3;

  BiliSearchController make(
    Future<List<BiliVideo>> Function(String keyword, int page) search,
  ) => BiliSearchController(search: search, pageSize: size);

  test('首屏搜到满页时认为还有下一页', () async {
    final c = make((_, _) async => _page(['a', 'b', 'c']));
    await c.submit('测试');

    expect(c.results.map((v) => v.bvid), ['a', 'b', 'c']);
    expect(c.hasMore, isTrue);
    expect(c.isSearching, isFalse);
    expect(c.error, isEmpty);
  });

  test('首屏不满页就是到底了', () async {
    final c = make((_, _) async => _page(['a', 'b']));
    await c.submit('测试');

    expect(c.hasMore, isFalse, reason: '返回条数 < pageSize 说明没有下一页了');
  });

  test('loadMore 请求下一页并追加结果', () async {
    final requested = <int>[];
    final c = make((_, page) async {
      requested.add(page);
      return page == 1 ? _page(['a', 'b', 'c']) : _page(['d', 'e']);
    });

    await c.submit('测试');
    await c.loadMore();

    expect(requested, [1, 2]);
    expect(c.results.map((v) => v.bvid), ['a', 'b', 'c', 'd', 'e']);
    expect(c.hasMore, isFalse);
  });

  test('跨页重复的 bvid 只保留一条', () async {
    final c = make(
      (_, page) async =>
          page == 1 ? _page(['a', 'b', 'c']) : _page(['b', 'c', 'd']),
    );

    await c.submit('测试');
    await c.loadMore();

    expect(c.results.map((v) => v.bvid), [
      'a',
      'b',
      'c',
      'd',
    ], reason: 'B 站相邻页会返回重复项，不去重列表里会出现同一个视频两次');
  });

  test('整页都是重复项时停止翻页，不会无限翻', () async {
    var calls = 0;
    final c = make((_, _) async {
      calls++;
      return _page(['a', 'b', 'c']); // 每一页都返回同样的三条
    });

    await c.submit('测试');
    await c.loadMore();

    expect(c.results, hasLength(3));
    expect(c.hasMore, isFalse, reason: '一条新的都没有就必须停，否则会对着同一页无限翻');

    await c.loadMore();
    expect(calls, 2, reason: '到底之后 loadMore 应该直接返回，不再发请求');
  });

  test('并发触发 loadMore 只会真正请求一次', () async {
    var calls = 0;
    final gate = Completer<void>();
    final c = make((_, page) async {
      calls++;
      if (page == 1) return _page(['a', 'b', 'c']);
      await gate.future;
      return _page(['d']);
    });

    await c.submit('测试');
    expect(calls, 1);

    // 滚动回调可能一帧内连喊好几次。
    final first = c.loadMore();
    final second = c.loadMore();
    final third = c.loadMore();
    gate.complete();
    await Future.wait([first, second, third]);

    expect(calls, 2, reason: '第一次之外的调用应该被 _loadingMore 挡掉');
    expect(c.results.map((v) => v.bvid), ['a', 'b', 'c', 'd']);
  });

  test('还没搜过时 loadMore 不做任何事', () async {
    var calls = 0;
    final c = make((_, _) async {
      calls++;
      return _page(['a']);
    });

    await c.loadMore();

    expect(calls, 0);
    expect(c.results, isEmpty);
  });

  test('新搜索会重置翻页状态', () async {
    final requested = <(String, int)>[];
    final c = make((keyword, page) async {
      requested.add((keyword, page));
      return _page([
        '$keyword-$page-1',
        '$keyword-$page-2',
        '$keyword-$page-3',
      ]);
    });

    await c.submit('第一次');
    await c.loadMore();
    await c.submit('第二次');

    expect(requested.last, ('第二次', 1), reason: '新搜索必须从第 1 页开始');
    expect(c.results, hasLength(3), reason: '旧结果要清空');
    expect(c.results.first.bvid, startsWith('第二次-1'));
  });

  test('新搜索发出后，上一次搜索的迟到响应被丢弃', () async {
    final slow = Completer<List<BiliVideo>>();
    final c = make((keyword, _) async {
      if (keyword == '慢') return slow.future;
      return _page(['fast']);
    });

    final stale = c.submit('慢');
    await c.submit('快');
    slow.complete(_page(['slow-1', 'slow-2', 'slow-3']));
    await stale;

    expect(c.results.map((v) => v.bvid), ['fast'], reason: '迟到的旧响应不能覆盖新搜索的结果');
    expect(c.keyword, '快');
  });

  group('翻页失败', () {
    test('保留已有结果，只记 moreError', () async {
      final c = make((_, page) async {
        if (page == 1) return _page(['a', 'b', 'c']);
        throw const BiliApiException(-412, '被风控了');
      });

      await c.submit('测试');
      await c.loadMore();

      expect(c.results, hasLength(3), reason: '翻页失败不该把已搜到的结果清掉');
      expect(c.moreError, '被风控了');
      expect(c.error, isEmpty, reason: '首屏错误和翻页错误要分开');
      expect(c.isLoadingMore, isFalse);
    });

    test('失败后不再自动重试，等用户点重试', () async {
      var calls = 0;
      final c = make((_, page) async {
        calls++;
        if (page == 1) return _page(['a', 'b', 'c']);
        throw const BiliApiException(-412, '被风控了');
      });

      await c.submit('测试');
      await c.loadMore();
      final afterFailure = calls;

      // 滚动回调还会继续喊，但不该把失败的请求打成循环。
      await c.loadMore();
      await c.loadMore();

      expect(calls, afterFailure);
    });

    test('retryMore 清掉错误并重新请求', () async {
      var failNext = true;
      final c = make((_, page) async {
        if (page == 1) return _page(['a', 'b', 'c']);
        if (failNext) {
          failNext = false;
          throw const BiliApiException(-412, '被风控了');
        }
        return _page(['d']);
      });

      await c.submit('测试');
      await c.loadMore();
      expect(c.moreError, isNotEmpty);

      await c.retryMore();

      expect(c.moreError, isEmpty);
      expect(c.results.map((v) => v.bvid), ['a', 'b', 'c', 'd']);
    });
  });
}
