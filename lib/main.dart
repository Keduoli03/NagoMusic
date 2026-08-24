import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:media_cache/media_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/services/debug_log_service.dart';
import 'app/services/haptic_service.dart';
import 'app/startup/library_warmup_service.dart';
import 'app/state/settings_state.dart';
import 'components/layout/liquid_glass.dart';
import 'app/services/media_notification_service.dart';
import 'app/services/db/dao/song_dao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须是 ensureInitialized() 之后第一件事：PlayerService._init() 会调
  // AppCacheSettings.ensureLoaded()，而 PlayerService.instance 是懒单例，
  // 可能在 main 里很早就被构造出来（比如下面的 MediaNotificationService.init()）。
  // 一旦 ensureLoaded() 先于这行跑，PrefGroup 的 onLoaded 回调拿到的就是
  // 一个 null 的 onLimitChanged，缓存大小限制会被静默地整个跳过。
  AppCacheSettings.onLimitChanged = AudioCacheService.instance.setMaxCacheBytes;
  // 画到系统栏底下。不开的话系统会给导航栏留出一条实底，浮动胶囊底栏就等于
  // 浮在一块满宽白板上。Android 15+ 本来就强制 edge-to-edge，这里显式声明是
  // 为了老设备行为一致。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await DebugLogService.instance.ensureLoaded();
  await FlutterDisplayMode.setHighRefreshRate();
  await MediaNotificationService.init();
  await AppThemeSettings.ensureLoaded();
  await Haptics.init();
  await AppLayoutSettings.ensureLoaded();
  // 着色器编译要花几十毫秒，提前跑掉；顺带探测 Impeller 可用性，免得进首页时
  // 底栏先闪一下实底再变成玻璃。
  if (AppLayoutSettings.bottomBarStyle.value == AppBottomBarStyle.liquidGlass) {
    await LiquidGlassSupport.ensureLoaded();
  }
  await AppBackgroundSettings.ensureLoaded();
  await PlayerStyleSettings.ensureLoaded();
  await SongListDisplaySettings.ensureLoaded();
  runApp(const NagoMusicApp());
  // Fire-and-forget warm-ups that run in parallel with the first frame so
  // per-page initState calls don't have to pay for these cold starts:
  //   - SharedPreferences.getInstance() reads its backing file once, then
  //     serves subsequent callers from the in-memory instance.
  //   - fetchAllCached() populates SongDao's static cache; every library
  //     page hits this the moment it initialises.
  SharedPreferences.getInstance();
  SongDao().fetchAllCached();
  // Pre-compute Albums/Artists groupings in the background so opening those
  // library pages from the drawer / "我的" is instant instead of triggering a
  // fresh isolate spawn.
  LibraryWarmupService.scheduleAppStartWarmup();
}
