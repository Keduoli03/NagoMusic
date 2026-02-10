import 'package:flutter/material.dart';

import '../../pages/home/home_page.dart';
import '../../pages/source/source_page.dart';
import '../../pages/songs/songs_page.dart';
import '../../pages/player/player_page.dart';
import '../../pages/player/lyrics/lyric_page.dart';
import '../../pages/settings/gradient_settings_page.dart';
import '../../pages/settings/lyrics_settings_page.dart';
import '../../pages/settings/cache_settings_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/library/albums_page.dart';
import '../../pages/library/artists_page.dart';
import '../../pages/library/playlists_page.dart';
import '../../pages/search/search_page.dart';

class AppRoutes {
  static const home = '/home';
  static const source = '/source';
  static const songs = '/songs';
  static const player = '/player';
  static const lyrics = '/player/lyrics';
  static const settings = '/settings';
  static const gradientSettings = '/settings/gradient';
  static const lyricsSettings = '/settings/lyrics';
  static const cacheSettings = '/settings/cache';
  static const artists = '/artists';
  static const albums = '/albums';
  static const playlists = '/playlists';
  static const search = '/search';
}

class AppRouter {
  static String get initialRoute => AppRoutes.home;

  static Map<String, WidgetBuilder> get routes => {
        AppRoutes.home: (_) => const HomePage(),
        AppRoutes.source: (_) => const SourcePage(),
        AppRoutes.songs: (_) => const SongsPage(),
        AppRoutes.player: (_) => const PlayerPage(),
        AppRoutes.lyrics: (_) => LyricPage(),
        AppRoutes.settings: (_) => const SettingsPage(),
        AppRoutes.gradientSettings: (_) => const GradientSettingsPage(),
        AppRoutes.lyricsSettings: (_) => const LyricsSettingsPage(),
        AppRoutes.cacheSettings: (_) => const CacheSettingsPage(),
        AppRoutes.artists: (_) => const ArtistsPage(),
        AppRoutes.albums: (_) => const AlbumsPage(),
        AppRoutes.playlists: (_) => const PlaylistsPage(),
        AppRoutes.search: (_) => const SearchPage(),
      };
}
