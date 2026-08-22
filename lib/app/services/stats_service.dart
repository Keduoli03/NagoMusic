import 'package:flutter/foundation.dart';

import '../state/player_state.dart';
import '../utils/format_utils.dart';
import 'db/db_constants.dart';
import 'db/db_helper.dart';

class DayListeningStat {
  final String dayKey;
  final int listenMs;
  final int playCount;

  const DayListeningStat({
    required this.dayKey,
    required this.listenMs,
    required this.playCount,
  });
}

class SongListeningStat {
  final String songId;
  final int listenMs;
  final int playCount;
  final int lastPlayedMs;

  const SongListeningStat({
    required this.songId,
    required this.listenMs,
    required this.playCount,
    required this.lastPlayedMs,
  });
}

class AlbumPlaybackStat {
  final String albumName;
  final int playCount;
  final int lastPlayedMs;

  const AlbumPlaybackStat({
    required this.albumName,
    required this.playCount,
    required this.lastPlayedMs,
  });
}

class PlaylistPlaybackStat {
  final String playlistId;
  final int playCount;
  final int lastPlayedMs;

  const PlaylistPlaybackStat({
    required this.playlistId,
    required this.playCount,
    required this.lastPlayedMs,
  });
}

class StatsTotals {
  final int listenMs;
  final int playCount;

  const StatsTotals({required this.listenMs, required this.playCount});
}

class StatsService {
  static final StatsService instance = StatsService._internal();

  StatsService._internal();

  DateTime? _lastTickAt;
  String? _currentSongId;
  int _currentSongPlayedMs = 0;
  bool _currentPlayCounted = false;
  int _pendingSongListenMs = 0;
  int _pendingSongPlayCount = 0;
  int _pendingDayListenMs = 0;
  int _pendingDayPlayCount = 0;
  bool _flushRunning = false;

  void onSnapshot(PlaybackSnapshot snapshot) {
    final song = snapshot.song;
    if (!snapshot.isPlaying || song == null) {
      _flushPending();
      _lastTickAt = null;
      return;
    }
    if (_currentSongId != song.id) {
      _flushPending();
      _currentSongId = song.id;
      _currentSongPlayedMs = 0;
      _currentPlayCounted = false;
    }
    final now = DateTime.now();
    final last = _lastTickAt;
    _lastTickAt = now;
    if (last == null) return;
    var deltaMs = now.difference(last).inMilliseconds;
    if (deltaMs <= 0) return;
    if (deltaMs > 10000) deltaMs = 10000;
    _currentSongPlayedMs += deltaMs;
    _pendingSongListenMs += deltaMs;
    _pendingDayListenMs += deltaMs;
    if (!_currentPlayCounted && _currentSongPlayedMs >= 30000) {
      _currentPlayCounted = true;
      _pendingSongPlayCount += 1;
      _pendingDayPlayCount += 1;
    }
    if (_pendingSongListenMs >= 15000 || _pendingDayListenMs >= 15000) {
      _flushPending();
    }
  }

  Future<void> flush() async {
    await _flushPending();
  }

  Future<List<DayListeningStat>> fetchMonthStats({
    required int year,
    required int month,
  }) async {
    final db = await DbHelper.instance.database;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final startKey = formatDayKey(start);
    final endKey = formatDayKey(end);
    final rows = await db.query(
      DbConstants.tableListeningDays,
      where: 'dayKey >= ? AND dayKey <= ?',
      whereArgs: [startKey, endKey],
      orderBy: 'dayKey ASC',
    );
    return rows
        .map(
          (row) => DayListeningStat(
            dayKey: row['dayKey'].toString(),
            listenMs: _parseInt(row['listenMs']),
            playCount: _parseInt(row['playCount']),
          ),
        )
        .toList();
  }

  /// Map of songId -> playCount for every song that has playback stats.
  /// Used to sort the songs list by play count.
  Future<Map<String, int>> fetchPlayCounts() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      columns: ['songId', 'playCount'],
    );
    final map = <String, int>{};
    for (final row in rows) {
      map[row['songId'].toString()] = _parseInt(row['playCount']);
    }
    return map;
  }

  /// Map of songId -> lastPlayedMs. Powers the home recommender's recency /
  /// time-of-day signals.
  Future<Map<String, int>> fetchLastPlayedTimestamps() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      columns: ['songId', 'lastPlayedMs'],
    );
    final map = <String, int>{};
    for (final row in rows) {
      map[row['songId'].toString()] = _parseInt(row['lastPlayedMs']);
    }
    return map;
  }

  Future<List<SongListeningStat>> fetchTopSongs({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      orderBy: 'playCount DESC, listenMs DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => SongListeningStat(
            songId: row['songId'].toString(),
            listenMs: _parseInt(row['listenMs']),
            playCount: _parseInt(row['playCount']),
            lastPlayedMs: _parseInt(row['lastPlayedMs']),
          ),
        )
        .toList();
  }

  Future<List<SongListeningStat>> fetchRecentSongs({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongStats,
      orderBy: 'lastPlayedMs DESC, playCount DESC, listenMs DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => SongListeningStat(
            songId: row['songId'].toString(),
            listenMs: _parseInt(row['listenMs']),
            playCount: _parseInt(row['playCount']),
            lastPlayedMs: _parseInt(row['lastPlayedMs']),
          ),
        )
        .toList();
  }

  Future<List<AlbumPlaybackStat>> fetchRecentAlbums({int limit = 20}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableAlbumStats,
      orderBy: 'lastPlayedMs DESC, playCount DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => AlbumPlaybackStat(
            albumName: row['albumName'].toString(),
            playCount: _parseInt(row['playCount']),
            lastPlayedMs: _parseInt(row['lastPlayedMs']),
          ),
        )
        .where((row) => row.albumName.trim().isNotEmpty)
        .toList();
  }

  Future<List<PlaylistPlaybackStat>> fetchRecentPlaylists({
    int limit = 20,
  }) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tablePlaylistStats,
      orderBy: 'lastPlayedMs DESC, playCount DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => PlaylistPlaybackStat(
            playlistId: row['playlistId'].toString(),
            playCount: _parseInt(row['playCount']),
            lastPlayedMs: _parseInt(row['lastPlayedMs']),
          ),
        )
        .where((row) => row.playlistId.trim().isNotEmpty)
        .toList();
  }

  Future<void> recordAlbumPlay(String albumName) async {
    final normalized = albumName.trim().isEmpty ? '未知专辑' : albumName.trim();
    await _recordEntityPlay(
      table: DbConstants.tableAlbumStats,
      idColumn: 'albumName',
      idValue: normalized,
    );
  }

  Future<void> recordPlaylistPlay(String playlistId) async {
    final normalized = playlistId.trim();
    if (normalized.isEmpty) return;
    await _recordEntityPlay(
      table: DbConstants.tablePlaylistStats,
      idColumn: 'playlistId',
      idValue: normalized,
    );
  }

  Future<StatsTotals> fetchTotalStats() async {
    final db = await DbHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT SUM(listenMs) AS totalListenMs, SUM(playCount) AS totalPlayCount FROM ${DbConstants.tableListeningDays}',
    );
    if (rows.isEmpty) {
      return const StatsTotals(listenMs: 0, playCount: 0);
    }
    final row = rows.first;
    return StatsTotals(
      listenMs: _parseInt(row['totalListenMs']),
      playCount: _parseInt(row['totalPlayCount']),
    );
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  Future<void> _flushPending() async {
    if (_flushRunning) return;
    final songId = _currentSongId;
    final songListenMs = _pendingSongListenMs;
    final songPlayCount = _pendingSongPlayCount;
    final dayListenMs = _pendingDayListenMs;
    final dayPlayCount = _pendingDayPlayCount;
    if (songId == null) return;
    if (songListenMs <= 0 &&
        songPlayCount <= 0 &&
        dayListenMs <= 0 &&
        dayPlayCount <= 0) {
      return;
    }
    _pendingSongListenMs = 0;
    _pendingSongPlayCount = 0;
    _pendingDayListenMs = 0;
    _pendingDayPlayCount = 0;
    _flushRunning = true;
    try {
      final db = await DbHelper.instance.database;
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final dayKey = formatDayKey(now);
      await db.transaction((txn) async {
        if (songListenMs > 0 || songPlayCount > 0) {
          final rows = await txn.query(
            DbConstants.tableSongStats,
            columns: ['listenMs', 'playCount'],
            where: 'songId = ?',
            whereArgs: [songId],
            limit: 1,
          );
          if (rows.isEmpty) {
            await txn.insert(DbConstants.tableSongStats, {
              'songId': songId,
              'listenMs': songListenMs,
              'playCount': songPlayCount,
              'lastPlayedMs': nowMs,
            });
          } else {
            final current = rows.first;
            final nextListenMs = _parseInt(current['listenMs']) + songListenMs;
            final nextPlayCount =
                _parseInt(current['playCount']) + songPlayCount;
            await txn.update(
              DbConstants.tableSongStats,
              {
                'listenMs': nextListenMs,
                'playCount': nextPlayCount,
                'lastPlayedMs': nowMs,
              },
              where: 'songId = ?',
              whereArgs: [songId],
            );
          }
        }
        if (dayListenMs > 0 || dayPlayCount > 0) {
          final rows = await txn.query(
            DbConstants.tableListeningDays,
            columns: ['listenMs', 'playCount'],
            where: 'dayKey = ?',
            whereArgs: [dayKey],
            limit: 1,
          );
          if (rows.isEmpty) {
            await txn.insert(DbConstants.tableListeningDays, {
              'dayKey': dayKey,
              'listenMs': dayListenMs,
              'playCount': dayPlayCount,
            });
          } else {
            final current = rows.first;
            final nextListenMs = _parseInt(current['listenMs']) + dayListenMs;
            final nextPlayCount =
                _parseInt(current['playCount']) + dayPlayCount;
            await txn.update(
              DbConstants.tableListeningDays,
              {'listenMs': nextListenMs, 'playCount': nextPlayCount},
              where: 'dayKey = ?',
              whereArgs: [dayKey],
            );
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('StatsService flush failed: $e');
      }
    } finally {
      _flushRunning = false;
    }
  }

  Future<void> _recordEntityPlay({
    required String table,
    required String idColumn,
    required String idValue,
  }) async {
    final db = await DbHelper.instance.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['playCount'],
        where: '$idColumn = ?',
        whereArgs: [idValue],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert(table, {
          idColumn: idValue,
          'playCount': 1,
          'lastPlayedMs': nowMs,
        });
        return;
      }
      await txn.update(
        table,
        {
          'playCount': _parseInt(rows.first['playCount']) + 1,
          'lastPlayedMs': nowMs,
        },
        where: '$idColumn = ?',
        whereArgs: [idValue],
      );
    });
  }

  // ---- Backup / restore ----

  /// Dumps all four stats tables as plain row maps for backup.
  Future<Map<String, List<Map<String, dynamic>>>> exportAll() async {
    final db = await DbHelper.instance.database;
    Future<List<Map<String, dynamic>>> dump(String table) async {
      final rows = await db.query(table);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    return {
      'songStats': await dump(DbConstants.tableSongStats),
      'dayStats': await dump(DbConstants.tableListeningDays),
      'albumStats': await dump(DbConstants.tableAlbumStats),
      'playlistStats': await dump(DbConstants.tablePlaylistStats),
    };
  }

  /// Merge-import stats: cumulative counters are ADDED to existing values,
  /// timestamps take the later value.
  Future<void> importMerge(Map<String, dynamic> data) async {
    final db = await DbHelper.instance.database;
    await db.transaction((txn) async {
      Future<void> mergeCounter(
        String table,
        String idCol,
        List rows,
        List<String> sumCols,
        List<String> maxCols,
      ) async {
        for (final raw in rows) {
          if (raw is! Map) continue;
          final row = raw.cast<String, dynamic>();
          final id = row[idCol]?.toString();
          if (id == null || id.isEmpty) continue;
          final existing = await txn.query(
            table,
            where: '$idCol = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert(table, row);
          } else {
            final cur = existing.first;
            final update = <String, dynamic>{};
            for (final c in sumCols) {
              update[c] = _parseInt(cur[c]) + _parseInt(row[c]);
            }
            for (final c in maxCols) {
              final a = _parseInt(cur[c]);
              final b = _parseInt(row[c]);
              update[c] = a > b ? a : b;
            }
            await txn.update(
              table,
              update,
              where: '$idCol = ?',
              whereArgs: [id],
            );
          }
        }
      }

      await mergeCounter(
        DbConstants.tableSongStats,
        'songId',
        (data['songStats'] as List?) ?? const [],
        ['listenMs', 'playCount'],
        ['lastPlayedMs'],
      );
      await mergeCounter(
        DbConstants.tableListeningDays,
        'dayKey',
        (data['dayStats'] as List?) ?? const [],
        ['listenMs', 'playCount'],
        const [],
      );
      await mergeCounter(
        DbConstants.tableAlbumStats,
        'albumName',
        (data['albumStats'] as List?) ?? const [],
        ['playCount'],
        ['lastPlayedMs'],
      );
      await mergeCounter(
        DbConstants.tablePlaylistStats,
        'playlistId',
        (data['playlistStats'] as List?) ?? const [],
        ['playCount'],
        ['lastPlayedMs'],
      );
    });
  }
}
