import 'package:shared_preferences/shared_preferences.dart';

import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import 'home_data_controller.dart';

/// 首页的播放 / 音源切换动作，从 [HomePage] 里抽出来方便单测。
///
/// 不持有 BuildContext：toast / signal 更新都通过回调交给调用方，这里只管
/// 播放队列与偏好持久化。
class HomeActionsController {
  final PlayerService _player;

  HomeActionsController({PlayerService? player})
    : _player = player ?? PlayerService.instance;

  /// 播放一组发现队列。歌单为空时调用 [onEmpty] 而不播放；否则先调用 [onStart]
  /// （调用方在这里同步标记"当前激活的发现卡"），再真正开始播放 —— 顺序不能换，
  /// 原实现里 UI 是先标记激活态、播放器再异步加载队列。
  Future<void> playDiscoveryQueue({
    required List<SongEntity> songs,
    required void Function() onEmpty,
    required void Function() onStart,
  }) async {
    if (songs.isEmpty) {
      onEmpty();
      return;
    }
    onStart();
    await _player.playQueue(songs, 0);
  }

  /// 持久化音源筛选偏好。signal 本身由调用方同步更新，这里只管落盘。
  Future<void> setFilter(String next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HomeDataController.prefsHomeFilterKey, next);
  }
}
