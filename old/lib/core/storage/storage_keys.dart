/// 存储键常量
///
/// 统一管理所有本地存储的键名，避免硬编码
abstract class StorageKeys {
  // ==================== 应用相关 ====================

  /// 是否首次启动
  static const isFirstLaunch = 'app_is_first_launch';

  /// 当前应用版本（用于版本迁移）
  static const appVersion = 'app_version';

  // ==================== 用户相关 ====================

  /// 用户 Token
  static const userToken = 'user_token';

  /// 用户 ID
  static const userId = 'user_id';

  /// 是否已登录
  static const isLoggedIn = 'user_is_logged_in';

  // ==================== 设置相关 ====================

  /// 主题模式（light/dark/system）
  static const themeMode = 'setting_theme_mode';
  static const playbackMode = 'player_playback_mode';

  /// 动态颜色主题（Android 12+）
  static const dynamicColorEnabled = 'setting_dynamic_color_enabled';

  static const playbackThemeMode = 'setting_playback_theme_mode';
  static const dynamicGradientEnabled = 'dynamic_gradient_enabled';
  static const dynamicGradientSaturation = 'dynamic_gradient_saturation';
  static const dynamicGradientHueShift = 'dynamic_gradient_hue_shift';

  /// 语言
  static const language = 'setting_language';

  /// 刷新率模式 (auto/high/low)
  static const refreshRateMode = 'setting_refresh_rate_mode';

  // ==================== 用户可扩展 ====================
  // 在此添加项目特定的键...
  static const musicSources = 'music_sources_v1';
  static const cachedSongs = 'music_cached_songs_v1';
  static const cacheSizeLimitMb = 'cache_size_limit_mb';
  static const enableSoftDecoding = 'enable_soft_decoding';
  static const cacheLocalCover = 'cache_local_cover';
  static const artworkPrefetchConcurrency = 'artwork_prefetch_concurrency';
  static const localMetadataConcurrency = 'local_metadata_concurrency';
  static const songsFilter = 'songs_filter';
  static const homeSongsFilter = 'home_songs_filter';

  static const songsSortKey = 'songs_sort_key';
  static const songsSortAscending = 'songs_sort_ascending';

  static const artistsSortKey = 'artists_sort_key';
  static const artistsSortAscending = 'artists_sort_ascending';
  static const artistsFilterUnknown = 'artists_filter_unknown';

  static const albumsSortKey = 'albums_sort_key';
  static const albumsSortAscending = 'albums_sort_ascending';
  static const albumsGridColumns = 'albums_grid_columns';

  static const lyricsFontSize = 'lyrics_font_size';
  static const lyricsLineGap = 'lyrics_line_gap';
  static const showLyricsTranslation = 'show_lyrics_translation';
  static const lyricsAlignment = 'lyrics_alignment';
  static const miniLyricsAlignment = 'mini_lyrics_alignment';
  static const lyricsActiveScale = 'lyrics_active_scale';
  static const lyricsActiveFontSize = 'lyrics_active_font_size';
  static const lyricsDragToSeek = 'lyrics_drag_to_seek';
  static const lyricsKaraokeEnabled = 'lyrics_karaoke_enabled';

  static const lastPlayedSongId = 'player_last_song_id';
  static const lastPlaybackQueue = 'player_last_queue_v1';
  static const lastPlaybackIndex = 'player_last_index';
  static const lastPlaybackPositionMs = 'player_last_position_ms';
  static const lastPlaybackDurationMs = 'player_last_duration_ms';
  static const showPlaylistCovers = 'show_playlist_covers';

  static const blockedArtists = 'blocked_artists';
  static const blockedAlbums = 'blocked_albums';

  static const showBlockedArtists = 'show_blocked_artists';
  static const showBlockedAlbums = 'show_blocked_albums';
  static const showBlockedLocalFolders = 'show_blocked_local_folders';
  static const showBlockedWebDavFolders = 'show_blocked_webdav_folders';

  /// Lyricon 服务开关
  static const lyriconEnabled = 'lyricon_enabled';

  /// Lyricon 强制逐字
  static const lyriconForceKaraoke = 'lyricon_force_karaoke';

  /// Lyricon 隐藏翻译
  static const lyriconHideTranslation = 'lyricon_hide_translation';

  /// 魅族状态栏歌词开关
  static const meizuLyricsEnabled = 'meizu_lyrics_enabled';
}
