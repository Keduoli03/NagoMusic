import 'dart:math';

import '../../app/state/song_state.dart';

/// Weighted recommender for the home page.
///
/// Everything is derived from data we already collect locally — no cross-user
/// signal, no ML. The point is to move the daily/heart/recommended lists off
/// pure `shuffle()` and onto a signal that reflects what the user actually
/// listens to, when they listen, and who they like.
///
/// ### Scoring dimensions
/// - **Play familiarity**: log-scaled `playCount` so heavy rotation lifts a
///   song without a single-obsession song dominating everything.
/// - **Recency**: sigmoid over "days since last played" — recently played
///   gets a small penalty (not stale-fresh), and week+ unheard gets a boost
///   (rediscovery). Never fully-played songs get a neutral score.
/// - **Time-of-day**: computes a per-song "typical listen hour" from the last
///   play timestamp; songs played close to the current hour bucket score
///   higher. Bucket size is 4h (morning / midday / afternoon / evening /
///   late-night / dawn).
/// - **Favorite anchor** (heart mode only): direct favorites always start
///   with a fixed baseline; same-artist / same-album non-favorites earn a
///   graded bonus based on how many of their peers you've hearted.
/// - **Diversity penalty**: after ranking, we walk the list top-down and
///   cap each artist and each album at a small quota. Prevents the front of
///   the list turning into "everything by one artist you binged last week".
///
/// Everything runs on the currently-visible source (local / a specific
/// WebDAV, etc.) — the caller filters `songs` before passing it in.
class HomeRecommender {
  static const int _artistQuota = 2;
  static const int _albumQuota = 3;
  static const int _heartFallbackSalt = 0x48454152;
  static const int _recommendedFallbackSalt = 0x5245434F;

  final DateTime now;
  final Map<String, int> playCounts;
  final Map<String, int> lastPlayedMs;
  final Set<String> favoriteIds;

  late final _random = Random(now.year * 10000 + now.month * 100 + now.day);

  HomeRecommender({
    required this.now,
    required this.playCounts,
    required this.lastPlayedMs,
    required this.favoriteIds,
  });

  /// Deterministic-per-day list of ~30 tracks that lean on the user's history
  /// without becoming a "top 30" replay.
  List<SongEntity> daily(List<SongEntity> pool, {int limit = 30}) {
    if (pool.isEmpty) return const [];
    // Cold start: user has never played anything in this pool — the score
    // engine has nothing to grip, so fall back to a stable daily shuffle.
    final anyHistory = pool.any(
      (s) => (playCounts[s.id] ?? 0) > 0 || (lastPlayedMs[s.id] ?? 0) > 0,
    );
    if (!anyHistory) {
      final copy = List<SongEntity>.of(pool)..shuffle(_random);
      return copy.take(limit).toList();
    }
    final scored = pool.map(_scoreForDaily).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return _diversify(scored, limit: limit);
  }

  /// Heart-mode: favorites first, then songs similar to what the user hearts,
  /// scored so heavy-listen favorites float above one-time hearts and unheard
  /// same-artist tracks earn a real boost.
  List<SongEntity> heart(List<SongEntity> pool, {int limit = 40}) {
    if (favoriteIds.isEmpty) {
      return _stableFallback(pool, limit: limit, salt: _heartFallbackSalt);
    }
    final favorites = pool.where((s) => favoriteIds.contains(s.id)).toList();
    if (favorites.isEmpty) {
      return _stableFallback(pool, limit: limit, salt: _heartFallbackSalt);
    }

    // Anchor sets so we know which artists / albums the user is attached to,
    // and how strongly (a favorited artist counted three times matters more
    // than one counted once).
    final artistAffinity = <String, int>{};
    final albumAffinity = <String, int>{};
    for (final song in favorites) {
      final artist = song.artist.trim();
      if (artist.isNotEmpty) {
        artistAffinity[artist] = (artistAffinity[artist] ?? 0) + 1;
      }
      final album = song.album?.trim() ?? '';
      if (album.isNotEmpty) {
        albumAffinity[album] = (albumAffinity[album] ?? 0) + 1;
      }
    }

    final scored =
        pool
            .map((s) => _scoreForHeart(s, artistAffinity, albumAffinity))
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return _diversify(scored, limit: limit);
  }

  /// Small "根据你喜欢的" strip: same signal as heart mode but drops the
  /// existing favorites so users see fresh candidates they haven't hearted
  /// yet. Falls back cleanly when there's nothing similar to lean on.
  ///
  /// 调用方如果**已经**为同一个 pool 算过 [heart] / [daily]，把结果通过
  /// [heartRanked] / [dailyRanked] 传进来即可复用 —— 否则这里会把整个曲库
  /// 重新打分排序一遍，而首页正好三样都要，等于同一份活干两三次。
  List<SongEntity> recommended(
    List<SongEntity> pool, {
    int limit = 6,
    List<SongEntity>? heartRanked,
    List<SongEntity>? dailyRanked,
  }) {
    final hasFavoriteInPool = pool.any((s) => favoriteIds.contains(s.id));
    if (!hasFavoriteInPool) {
      return _stableFallback(
        pool,
        limit: limit,
        salt: _recommendedFallbackSalt,
      );
    }
    final ranked = heartRanked ?? heart(pool, limit: limit * 4);
    final list = ranked.where((s) => !favoriteIds.contains(s.id)).toList();
    if (list.length >= limit) return list.take(limit).toList();
    // Backfill with daily so the row is never empty.
    final seen = list.map((s) => s.id).toSet();
    final backfill = (dailyRanked ?? daily(pool, limit: limit * 2))
        .where((s) => !seen.contains(s.id))
        .toList();
    return [...list, ...backfill].take(limit).toList();
  }

  List<SongEntity> _stableFallback(
    List<SongEntity> pool, {
    required int limit,
    required int salt,
  }) {
    final daySeed = now.year * 10000 + now.month * 100 + now.day;
    final copy = List<SongEntity>.of(pool)..shuffle(Random(daySeed ^ salt));
    return copy.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // Scoring internals
  // ---------------------------------------------------------------------------

  _Scored _scoreForDaily(SongEntity song) {
    final familiarity = _familiarityScore(song);
    final recency = _recencyScore(song);
    final timeOfDay = _timeOfDayScore(song);
    final favBonus = favoriteIds.contains(song.id) ? 0.4 : 0.0;
    // Small deterministic-per-day jitter so ties don't always resolve the
    // same way every load — but two calls in the same day still agree.
    final jitter = (_random.nextDouble() - 0.5) * 0.08;
    final score =
        familiarity * 0.35 +
        recency * 0.25 +
        timeOfDay * 0.20 +
        favBonus +
        jitter;
    return _Scored(song, score);
  }

  _Scored _scoreForHeart(
    SongEntity song,
    Map<String, int> artistAffinity,
    Map<String, int> albumAffinity,
  ) {
    final isFav = favoriteIds.contains(song.id);
    if (isFav) {
      // Favorites always in — familiarity and recency decide ordering.
      final familiarity = _familiarityScore(song);
      final recency = _recencyScore(song);
      final timeOfDay = _timeOfDayScore(song);
      return _Scored(
        song,
        1.2 + familiarity * 0.25 + recency * 0.15 + timeOfDay * 0.10,
      );
    }
    final artist = song.artist.trim();
    final album = song.album?.trim() ?? '';
    final artistBoost = artist.isEmpty
        ? 0.0
        : _saturate(artistAffinity[artist] ?? 0, cap: 5) * 0.6;
    final albumBoost = album.isEmpty
        ? 0.0
        : _saturate(albumAffinity[album] ?? 0, cap: 4) * 0.4;
    final anchor = artistBoost + albumBoost;
    if (anchor <= 0) {
      // No affinity connection — skip.
      return _Scored(song, 0);
    }
    final familiarity = _familiarityScore(song);
    final timeOfDay = _timeOfDayScore(song);
    // Small "not listened lately" bonus so heart mode surfaces unheard peers
    // rather than always the same rotation.
    final freshness = _freshnessBonus(song);
    return _Scored(
      song,
      anchor + familiarity * 0.20 + timeOfDay * 0.15 + freshness * 0.10,
    );
  }

  /// log1p(playCount) normalised so ~50 plays saturates.
  double _familiarityScore(SongEntity song) {
    final plays = playCounts[song.id] ?? 0;
    if (plays <= 0) return 0.0;
    // log(plays+1) / log(51) so 50 plays -> 1.0, 5 plays -> ~0.46
    return (log(plays + 1) / log(51)).clamp(0.0, 1.2);
  }

  /// U-shaped: never played -> 0.3 (neutral rediscovery invite),
  /// played long ago -> up to 1.0, played today -> near 0.
  double _recencyScore(SongEntity song) {
    final lastMs = lastPlayedMs[song.id] ?? 0;
    if (lastMs <= 0) return 0.3;
    final daysSince = (now.millisecondsSinceEpoch - lastMs) / 86400000.0;
    if (daysSince < 0.5) return 0.05; // just played
    if (daysSince < 2) return 0.35;
    if (daysSince < 7) return 0.7;
    if (daysSince < 30) return 1.0; // sweet spot for rediscovery
    return 0.6; // ancient — still eligible but not the priority
  }

  /// +1.0 when the song was last played at the same 4-hour slot as now,
  /// tailing off across neighbouring slots.
  double _timeOfDayScore(SongEntity song) {
    final lastMs = lastPlayedMs[song.id] ?? 0;
    if (lastMs <= 0) return 0.0;
    final past = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final currentBucket = now.hour ~/ 4;
    final pastBucket = past.hour ~/ 4;
    // Circular distance across 6 buckets.
    final rawDelta = (currentBucket - pastBucket).abs();
    final delta = rawDelta > 3 ? 6 - rawDelta : rawDelta;
    switch (delta) {
      case 0:
        return 1.0;
      case 1:
        return 0.55;
      case 2:
        return 0.2;
      default:
        return 0.0;
    }
  }

  double _freshnessBonus(SongEntity song) {
    final lastMs = lastPlayedMs[song.id] ?? 0;
    if (lastMs <= 0) return 1.0;
    final daysSince = (now.millisecondsSinceEpoch - lastMs) / 86400000.0;
    if (daysSince > 14) return 1.0;
    if (daysSince > 7) return 0.6;
    return 0.0;
  }

  double _saturate(int count, {required int cap}) {
    if (count <= 0) return 0.0;
    if (count >= cap) return 1.0;
    return count / cap;
  }

  /// Walk the scored list top-down, dropping picks that would exceed the
  /// per-artist or per-album quota; anything skipped is retried on a second
  /// pass with looser quotas so we always fill `limit`.
  List<SongEntity> _diversify(List<_Scored> scored, {required int limit}) {
    final chosen = <SongEntity>[];
    final artistCounts = <String, int>{};
    final albumCounts = <String, int>{};
    final skipped = <_Scored>[];
    for (final entry in scored) {
      if (chosen.length >= limit) break;
      final artist = entry.song.artist.trim();
      final album = entry.song.album?.trim() ?? '';
      final artistExceeded =
          artist.isNotEmpty && (artistCounts[artist] ?? 0) >= _artistQuota;
      final albumExceeded =
          album.isNotEmpty && (albumCounts[album] ?? 0) >= _albumQuota;
      if (artistExceeded || albumExceeded) {
        skipped.add(entry);
        continue;
      }
      chosen.add(entry.song);
      if (artist.isNotEmpty) {
        artistCounts[artist] = (artistCounts[artist] ?? 0) + 1;
      }
      if (album.isNotEmpty) {
        albumCounts[album] = (albumCounts[album] ?? 0) + 1;
      }
    }
    // Second pass — fill the tail with previously-skipped songs if we still
    // haven't hit the target, no more quota checks.
    for (final entry in skipped) {
      if (chosen.length >= limit) break;
      chosen.add(entry.song);
    }
    return chosen;
  }
}

class _Scored {
  final SongEntity song;
  final double score;
  const _Scored(this.song, this.score);
}
