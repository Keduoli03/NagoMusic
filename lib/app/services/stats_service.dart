import 'package:flutter/foundation.dart';

import '../state/player_state.dart';
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

class StatsTotals {
  final int listenMs;
  final int playCount;

  const StatsTotals({
    required this.listenMs,
    required this.playCount,
  });
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
    final startKey = _dayKey(start);
    final endKey = _dayKey(end);
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

  String _dayKey(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
      final dayKey = _dayKey(now);
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
            await txn.insert(
              DbConstants.tableSongStats,
              {
                'songId': songId,
                'listenMs': songListenMs,
                'playCount': songPlayCount,
                'lastPlayedMs': nowMs,
              },
            );
          } else {
            final current = rows.first;
            final nextListenMs =
                _parseInt(current['listenMs']) + songListenMs;
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
            await txn.insert(
              DbConstants.tableListeningDays,
              {
                'dayKey': dayKey,
                'listenMs': dayListenMs,
                'playCount': dayPlayCount,
              },
            );
          } else {
            final current = rows.first;
            final nextListenMs =
                _parseInt(current['listenMs']) + dayListenMs;
            final nextPlayCount =
                _parseInt(current['playCount']) + dayPlayCount;
            await txn.update(
              DbConstants.tableListeningDays,
              {
                'listenMs': nextListenMs,
                'playCount': nextPlayCount,
              },
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
}
