import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/block_list_service.dart';
import '../services/db/dao/song_dao.dart';
import '../state/song_state.dart';
import '../utils/cache_version_store.dart';
import '../utils/page_cache_store.dart';
import '../../pages/library/albums_page.dart';
import '../../pages/library/artists_page.dart';

/// Kicks off idle-time work that pre-computes derived data users are likely
/// to hit within the first few seconds. Everything here is a strict prefetch —
/// if it fails, the page still recomputes on demand.
///
/// Called from `main.dart` after `runApp()`, so it never blocks first frame.
class LibraryWarmupService {
  LibraryWarmupService._();

  static bool _scheduled = false;

  /// Idempotent. Safe to call more than once — extra invocations are no-ops.
  static void scheduleAppStartWarmup() {
    if (_scheduled) return;
    _scheduled = true;
    // Delay past first frame + initial page loads so we don't compete with
    // the paint pipeline for the isolate/main-thread microtask queue.
    Future<void>.delayed(const Duration(milliseconds: 900), () async {
      try {
        await _warmAlbumsAndArtists();
      } catch (_) {
        // Prefetch failures are non-fatal; the pages will recompute on entry.
      }
    });
  }

  static Future<void> _warmAlbumsAndArtists() async {
    // Wait on the same in-flight DB read that main.dart kicked off — this
    // returns instantly if it already completed.
    final songs = await SongDao().fetchAllCached();
    if (songs.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final songVersion = CacheVersionStore.instance.getVersion(
      SongDao.cacheVersionScope,
    );

    await _warmAlbums(prefs, songs, songVersion);
    await _warmArtists(prefs, songs, songVersion);
  }

  static Future<void> _warmAlbums(
    SharedPreferences prefs,
    List<SongEntity> songs,
    int songVersion,
  ) async {
    final sortMode =
        (prefs.getString(albumsPrefsSortMode)?.trim().isNotEmpty ?? false)
        ? prefs.getString(albumsPrefsSortMode)!.trim()
        : albumsDefaultSortMode;
    final ascending =
        prefs.getBool(albumsPrefsSortAscending) ?? albumsDefaultAscending;
    final blockedSorted = (await BlockListService.instance.load(
      albumsPrefsBlockedAlbums,
    )).toList()..sort();
    final cacheKey = albumsCacheKeyForVersion(
      songVersion: songVersion,
      sortMode: sortMode,
      ascending: ascending,
      blockedSorted: blockedSorted,
    );
    // Already computed (e.g. user visited the page during startup) — leave
    // the LRU entry alone so recency ordering stays accurate.
    if (PageCacheStore.instance.get<List<AlbumGroup>>(
          albumsCacheScope,
          cacheKey,
        ) !=
        null) {
      return;
    }
    final groups = await compute(buildAlbumGroups, {
      'songs': songs.map((e) => e.toMap()).toList(),
      'blocked': blockedSorted,
      'sortMode': sortMode,
      'ascending': ascending,
    });
    final mapped = groups
        .map(
          (e) => AlbumGroup(
            name: e['name'] as String,
            songCount: e['songCount'] as int,
            representative: SongEntity.fromMap(
              (e['representative'] as Map).cast<String, dynamic>(),
            ),
          ),
        )
        .toList();
    PageCacheStore.instance.set(albumsCacheScope, cacheKey, mapped);
  }

  static Future<void> _warmArtists(
    SharedPreferences prefs,
    List<SongEntity> songs,
    int songVersion,
  ) async {
    final sortKey =
        (prefs.getString(artistsPrefsSortKey)?.trim().isNotEmpty ?? false)
        ? prefs.getString(artistsPrefsSortKey)!.trim()
        : artistsDefaultSortKey;
    final ascending =
        prefs.getBool(artistsPrefsSortAscending) ?? artistsDefaultAscending;
    final filterUnknown =
        prefs.getBool(artistsPrefsFilterUnknown) ?? artistsDefaultFilterUnknown;
    final blockedSorted = (await BlockListService.instance.load(
      artistsPrefsBlockedArtists,
    )).toList()..sort();
    final cacheKey = artistsCacheKeyForVersion(
      songVersion: songVersion,
      sortKey: sortKey,
      ascending: ascending,
      filterUnknown: filterUnknown,
      blockedSorted: blockedSorted,
    );
    if (PageCacheStore.instance.get<List<ArtistGroup>>(
          artistsCacheScope,
          cacheKey,
        ) !=
        null) {
      return;
    }
    final groups = await compute(buildArtistGroups, {
      'songs': songs.map((e) => e.toMap()).toList(),
      'blocked': blockedSorted,
      'sortKey': sortKey,
      'ascending': ascending,
      'filterUnknown': filterUnknown,
    });
    final mapped = groups
        .map(
          (e) => ArtistGroup(
            name: e['name'] as String,
            songCount: e['songCount'] as int,
            albumCount: e['albumCount'] as int,
            representative: SongEntity.fromMap(
              (e['representative'] as Map).cast<String, dynamic>(),
            ),
          ),
        )
        .toList();
    PageCacheStore.instance.set(artistsCacheScope, cacheKey, mapped);
  }
}
