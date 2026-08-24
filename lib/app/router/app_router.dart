import 'package:flutter/material.dart';

import '../../pages/home/home_page.dart';
import '../../pages/source/source_page.dart';
import '../../pages/songs/songs_page.dart';
import '../../pages/player/player_page.dart';
import '../../pages/player/lyrics/lyric_page.dart';
import '../../pages/profile/profile_page.dart';
import '../../pages/settings/gradient_settings_page.dart';
import '../../pages/settings/lyrics_settings_page.dart';
import '../../pages/settings/notification_settings_page.dart';
import '../../pages/settings/app_appearance_settings_page.dart';
import '../../pages/settings/player_settings_page.dart';
import '../../pages/settings/cache_settings_page.dart';
import '../../pages/settings/listening_stats_page.dart';
import '../../pages/settings/backup_restore_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/settings/version_info_page.dart';
import '../../pages/library/albums_page.dart';
import '../../pages/library/artists_page.dart';
import '../../pages/library/folders_page.dart';
import '../../pages/library/playlists_page.dart';
import '../../pages/search/search_page.dart';
import '../../pages/bili/bili_page.dart';
import '../../pages/bili/bili_login_page.dart';
import '../../pages/bili/bili_search_page.dart';
import '../../pages/bili/bili_recent_page.dart';
import '../../pages/bili/bili_profile_page.dart';
import '../../app/state/settings_state.dart';
import '../../app/utils/primary_shell_scope.dart';
import '../../components/layout/modern_navigation_bar.dart';

class AppRoutes {
  static const home = '/home';
  static const source = '/source';
  static const songs = '/songs';
  static const player = '/player';
  static const lyrics = '/player/lyrics';
  static const settings = '/settings';
  static const appAppearanceSettings = '/settings/app-appearance';
  static const gradientSettings = '/settings/gradient';
  static const lyricsSettings = '/settings/lyrics';
  static const notificationSettings = '/settings/notifications';
  static const playerSettings = '/settings/player';
  static const cacheSettings = '/settings/cache';
  static const listeningStats = '/settings/listening-stats';
  static const dataBackup = '/settings/data-backup';
  static const versionInfo = '/settings/version-info';
  static const artists = '/artists';
  static const albums = '/albums';
  static const playlists = '/playlists';
  static const folders = '/folders';
  static const search = '/search';
  static const profile = '/profile';
  static const bili = '/bili';
  static const biliLogin = '/bili/login';
  static const biliSearch = '/bili/search';
  static const biliRecent = '/bili/recent';
  static const biliProfile = '/bili/profile';
}

class AppRouter {
  static String get initialRoute => AppRoutes.home;

  static Map<String, WidgetBuilder> get routes => {
    AppRoutes.home: (_) => const _PrimaryNavigationShell(),
    AppRoutes.source: (_) => const SourcePage(),
    AppRoutes.songs: (_) => const SongsPage(),
    AppRoutes.player: (_) => const PlayerPage(),
    AppRoutes.lyrics: (_) => LyricPage(),
    AppRoutes.settings: (_) => const SettingsPage(),
    AppRoutes.appAppearanceSettings: (_) => const AppAppearanceSettingsPage(),
    AppRoutes.gradientSettings: (_) => const GradientSettingsPage(),
    AppRoutes.lyricsSettings: (_) => const LyricsSettingsPage(),
    AppRoutes.notificationSettings: (_) => const NotificationSettingsPage(),
    AppRoutes.playerSettings: (_) => const PlayerSettingsPage(),
    AppRoutes.cacheSettings: (_) => const CacheSettingsPage(),
    AppRoutes.listeningStats: (_) => const ListeningStatsPage(),
    AppRoutes.dataBackup: (_) => const BackupRestorePage(),
    AppRoutes.versionInfo: (_) => const VersionInfoPage(),
    AppRoutes.artists: (_) => const ArtistsPage(),
    AppRoutes.albums: (_) => const AlbumsPage(),
    AppRoutes.playlists: (_) => const PlaylistsPage(),
    AppRoutes.folders: (_) => const FoldersPage(),
    AppRoutes.search: (_) => const SearchPage(),
    AppRoutes.profile: (_) => const ProfilePage(),
    AppRoutes.bili: (_) => const BiliPage(),
    AppRoutes.biliLogin: (_) => const BiliLoginPage(),
    AppRoutes.biliSearch: (_) => const BiliSearchPage(),
    AppRoutes.biliRecent: (_) => const BiliRecentPage(),
    AppRoutes.biliProfile: (_) => const BiliProfilePage(),
  };
}

class _PrimaryNavigationShell extends StatefulWidget {
  const _PrimaryNavigationShell();

  @override
  State<_PrimaryNavigationShell> createState() =>
      _PrimaryNavigationShellState();
}

class _PrimaryNavigationShellState extends State<_PrimaryNavigationShell> {
  int _currentIndex = 0;
  final List<Widget?> _pages = <Widget?>[const HomePage(), null, null, null];
  bool _warmupScheduled = false;

  Widget _buildPage(int index) {
    return switch (index) {
      0 => const HomePage(),
      1 => const SongsPage(),
      2 => const BiliPage(),
      3 => const ProfilePage(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  void initState() {
    super.initState();
    primaryNavigationShellActive = true;
    primaryNavigationIndex.value = _currentIndex;
    primaryNavigationIndex.addListener(_handleExternalSelection);
  }

  @override
  void dispose() {
    primaryNavigationIndex.removeListener(_handleExternalSelection);
    primaryNavigationShellActive = false;
    super.dispose();
  }

  void _handleExternalSelection() {
    _select(primaryNavigationIndex.value);
  }

  void _select(int index) {
    if (_currentIndex == index || index < 0 || index > 3) return;
    setState(() {
      _pages[index] ??= _buildPage(index);
      _currentIndex = index;
    });
    if (primaryNavigationIndex.value != index) {
      primaryNavigationIndex.value = index;
    }
  }

  /// Build the remaining tabs during idle time so their DB reads and first
  /// frame happen while the user is still looking at Home. Subsequent taps on
  /// the bottom bar just flip IndexedStack.index — no cold start.
  void _scheduleWarmup() {
    if (_warmupScheduled) return;
    _warmupScheduled = true;
    // Give Home one full frame to settle first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Then spread the remaining pages across idle slots so we don't stall
      // the very next frame with three heavy initState() runs at once.
      _warmOne(1, delay: const Duration(milliseconds: 250));
      _warmOne(2, delay: const Duration(milliseconds: 700));
      _warmOne(3, delay: const Duration(milliseconds: 1100));
    });
  }

  void _warmOne(int index, {required Duration delay}) {
    Future<void>.delayed(delay, () {
      if (!mounted) return;
      if (_pages[index] != null) return;
      setState(() {
        _pages[index] = _buildPage(index);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppNavigationStyle>(
      valueListenable: AppLayoutSettings.navigationStyle,
      builder: (context, navigationStyle, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppLayoutSettings.tabletMode,
          builder: (context, tabletMode, _) {
            final useBottomNavigation =
                navigationStyle == AppNavigationStyle.bottomBar && !tabletMode;
            if (!useBottomNavigation) return const HomePage();

            _scheduleWarmup();

            return PopScope(
              canPop: _currentIndex == 0,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && _currentIndex != 0) _select(0);
              },
              child: PrimaryShellMarker(
                child: PrimaryNavigationScope(
                  currentIndex: _currentIndex,
                  onSelected: _select,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: List.generate(
                      _pages.length,
                      (index) => _pages[index] ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
