import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nagomusic/pages/home/home_data_controller.dart';

/// 首页 controller 的可测子集。
///
/// [HomeDataController.refreshAll] / [refreshWebDavCounts] 需要 SongDao 和一堆
/// 私有单例（PlaylistsService / StatsService / WebDavSourceRepository 等，构造器
/// 都是 `_internal()`，测试里伪造不了，repo 也没有 sqflite 测试底座），这部分和
/// 阶段 6 跳过 PlaylistDetailController 测试是同一个原因。
///
/// 但有两处**静默失效**风险必须钉死，它们正是这次搬运可能打错的地方：
/// - prefs key（filter 偏好键）
/// - 缓存 scope key（首页计数缓存和其他页面共用 PageCacheStore，scope 打错字会
///   静默破坏跨页面缓存失效，测试还抓不到）
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadFilterPref 未设置时默认 all', () async {
    final controller = HomeDataController();
    expect(await controller.loadFilterPref(), 'all');
  });

  test('loadFilterPref 读回已存的值 —— 防止 prefs key 在搬运中打错字', () async {
    SharedPreferences.setMockInitialValues({
      HomeDataController.prefsHomeFilterKey: 'webdav:abc',
    });
    final controller = HomeDataController();
    expect(await controller.loadFilterPref(), 'webdav:abc');
  });

  test('currentCacheKey 以 song 库版本号为前缀 —— 防止 scope key 打错字', () {
    final controller = HomeDataController();
    expect(controller.currentCacheKey(), startsWith('songv:'));
  });
}
