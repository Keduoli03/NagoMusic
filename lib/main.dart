import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/services/debug_log_service.dart';
import 'app/services/haptic_service.dart';
import 'app/startup/library_warmup_service.dart';
import 'app/state/settings_state.dart';
import 'app/services/media_notification_service.dart';
import 'app/services/db/dao/song_dao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugLogService.instance.ensureLoaded();
  await FlutterDisplayMode.setHighRefreshRate();
  await MediaNotificationService.init();
  await AppThemeSettings.ensureLoaded();
  await Haptics.init();
  await AppLayoutSettings.ensureLoaded();
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
