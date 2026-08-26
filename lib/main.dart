import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:media_cache/media_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/services/log/log.dart';
import 'app/services/bili/bili_collection_service.dart';
import 'app/services/haptic_service.dart';
import 'app/startup/library_warmup_service.dart';
import 'app/state/settings_state.dart';
import 'app/services/media_notification_service.dart';
import 'app/services/db/dao/song_dao.dart';

Future<void> main() => runGuardedApp(_startApp);

// runZonedGuarded 要能兜住 framework 的异步异常，binding 就必须在它的 zone
// 内部初始化——所以这里是 _startApp 的第一行，而不是 main 的第一行。
Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须是 ensureInitialized() 之后第一件事：PlayerService._init() 会调
  // AppCacheSettings.ensureLoaded()，而 PlayerService.instance 是懒单例，
  // 可能在 main 里很早就被构造出来（比如下面的 MediaNotificationService.init()）。
  // 一旦 ensureLoaded() 先于这行跑，PrefGroup 的 onLoaded 回调拿到的就是
  // 一个 null 的 onLimitChanged，缓存大小限制会被静默地整个跳过。
  AppCacheSettings.onLimitChanged = AudioCacheService.instance.setMaxCacheBytes;
  // 日志**不等**：AppLog 在就绪前会把消息排在内存里，ensureLoaded() 完成后补写
  // 进文件。所以启动期的异常照样留得下来，但那次文件读不必挡在首帧前面。
  unawaited(AppLog.instance.ensureLoaded());

  // 首帧要用到的设置一次并行读完。
  //
  // 这些 PrefGroup 各自都是「await SharedPreferences.getInstance() 再遍历自己的
  // 条目」——真正的开销只有第一次那回文件读，之后全是内存操作。原来一条条 await
  // 排下来，等于把同一个 Future 串成了六轮微任务；并成一组是等价的，但少了那几
  // 轮往返。
  await Future.wait([
    AppThemeSettings.ensureLoaded(),
    AppLayoutSettings.ensureLoaded(),
    AppBackgroundSettings.ensureLoaded(),
    PlayerStyleSettings.ensureLoaded(),
    SongListDisplaySettings.ensureLoaded(),
  ]);

  // 画到系统栏底下。不开的话系统会给导航栏留出一条实底，浮动胶囊底栏就等于
  // 浮在一块满宽白板上。Android 15+ 本来就强制 edge-to-edge，这里显式声明是
  // 为了老设备行为一致。
  //
  // 这条必须在首帧之前生效——它改的是 padding，等首帧画完再切会让整个布局跳一下。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const NagoMusicApp());

  // 以下都不是首帧需要的东西，全部放到 runApp 之后，和第一帧的光栅化并行跑。
  //
  // 之前它们是 runApp 前的串行 await，等于把「查询显示器支持的刷新率」「问一遍
  // 通知权限」「构造 PlayerService 和它那一堆流订阅」全垫在了用户看到第一个像素
  // 之前。这几件事都跟首帧长什么样没有关系。
  FlutterDisplayMode.setHighRefreshRate();
  Haptics.init();
  MediaNotificationService.init();
  //   - SharedPreferences.getInstance() reads its backing file once, then
  //     serves subsequent callers from the in-memory instance.
  //   - fetchAllCached() populates SongDao's static cache; every library
  //     page hits this the moment it initialises.
  SharedPreferences.getInstance();
  BiliCollectionService.instance.ensureLoaded();
  SongDao().fetchAllCached();
  // Pre-compute Albums/Artists groupings in the background so opening those
  // library pages from the drawer / "我的" is instant instead of triggering a
  // fresh isolate spawn.
  LibraryWarmupService.scheduleAppStartWarmup();
}
