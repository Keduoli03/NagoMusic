import 'package:sqflite/sqflite.dart';

import '../db_constants.dart';
import '../db_helper.dart';
import '../../../state/song_state.dart';
import '../../../utils/cache_version_store.dart';

class SongDao {
  static const String cacheVersionScope = 'song_library';
  static const int _maxIdsPerQuery = 500;
  static List<SongEntity>? _cachedAll;
  static Future<List<SongEntity>>? _cachedAllFuture;

  Future<int> upsertSongs(List<SongEntity> songs) async {
    if (songs.isEmpty) return 0;
    final db = await DbHelper.instance.database;
    final uniqueIds = songs.map((song) => song.id).toSet().toList();
    final added = await db.transaction<int>((txn) async {
      final existingIds = <String>{};
      for (
        var offset = 0;
        offset < uniqueIds.length;
        offset += _maxIdsPerQuery
      ) {
        final end = (offset + _maxIdsPerQuery).clamp(0, uniqueIds.length);
        final ids = uniqueIds.sublist(offset, end);
        final placeholders = List.filled(ids.length, '?').join(',');
        final rows = await txn.query(
          DbConstants.tableSongs,
          columns: ['id'],
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
        existingIds.addAll(rows.map((row) => row['id']).whereType<String>());
      }

      final batch = txn.batch();
      for (final song in songs) {
        batch.insert(
          DbConstants.tableSongs,
          song.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      return uniqueIds.length - existingIds.length;
    });
    _cachedAll = null;
    CacheVersionStore.instance.bump(cacheVersionScope);
    return added;
  }

  Future<int> countBySource(String sourceId) async {
    final db = await DbHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM ${DbConstants.tableSongs} WHERE sourceId = ?',
      [sourceId],
    );
    if (result.isEmpty) return 0;
    final value = result.first['total'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<int> countAll() async {
    final db = await DbHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM ${DbConstants.tableSongs}',
    );
    if (result.isEmpty) return 0;
    final value = result.first['total'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<int> countLocal() async {
    return countBySource('local');
  }

  Future<int> countRemote() async {
    final db = await DbHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM ${DbConstants.tableSongs} WHERE sourceId != ?',
      ['local'],
    );
    if (result.isEmpty) return 0;
    final value = result.first['total'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<SongEntity>> fetchAll({String? sourceId}) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongs,
      where: sourceId == null ? null : 'sourceId = ?',
      whereArgs: sourceId == null ? null : [sourceId],
      orderBy: 'title COLLATE NOCASE',
    );
    return rows.map(SongEntity.fromMap).toList();
  }

  Future<List<SongEntity>> fetchAllCached() async {
    final cached = _cachedAll;
    if (cached != null) return cached;
    final inflight = _cachedAllFuture;
    if (inflight != null) return inflight;
    final future = fetchAll();
    _cachedAllFuture = future;
    final list = await future;
    _cachedAll = list;
    _cachedAllFuture = null;
    return list;
  }

  Future<List<SongEntity>> fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final db = await DbHelper.instance.database;
    final map = <String, SongEntity>{};
    // 按 _maxIdsPerQuery 切批，理由和 upsertSongs 一样：Android 自带的 SQLite
    // 默认 SQLITE_MAX_VARIABLE_NUMBER 是 999，一条 `IN (?,?,…)` 塞满整份
    // playlist.songIds（大歌单轻松上千）会直接抛异常，不是慢，是打不开页面。
    for (var offset = 0; offset < ids.length; offset += _maxIdsPerQuery) {
      final end = (offset + _maxIdsPerQuery).clamp(0, ids.length);
      final chunk = ids.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        DbConstants.tableSongs,
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final song = SongEntity.fromMap(row);
        map[song.id] = song;
      }
    }
    return ids.map((id) => map[id]).whereType<SongEntity>().toList();
  }

  Future<Set<String>> fetchIdsBySource(String sourceId) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      DbConstants.tableSongs,
      columns: ['id'],
      where: 'sourceId = ?',
      whereArgs: [sourceId],
    );
    return rows.map((row) => row['id']).whereType<String>().toSet();
  }

  Future<int> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final db = await DbHelper.instance.database;
    var result = 0;
    // 同 fetchByIds：不切批的话，一次删掉一个大歌单/整个音源会撞上 SQLite 的
    // 变量数上限。
    for (var offset = 0; offset < ids.length; offset += _maxIdsPerQuery) {
      final end = (offset + _maxIdsPerQuery).clamp(0, ids.length);
      final chunk = ids.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      result += await db.delete(
        DbConstants.tableSongs,
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
    _cachedAll = null;
    CacheVersionStore.instance.bump(cacheVersionScope);
    return result;
  }

  Future<int> deleteBySourceAndMaxDuration({
    required String sourceId,
    required int maxDurationMs,
  }) async {
    final db = await DbHelper.instance.database;
    final result = await db.delete(
      DbConstants.tableSongs,
      where: 'sourceId = ? AND durationMs IS NOT NULL AND durationMs < ?',
      whereArgs: [sourceId, maxDurationMs],
    );
    _cachedAll = null;
    CacheVersionStore.instance.bump(cacheVersionScope);
    return result;
  }

  Future<int> deleteBySource(String sourceId) async {
    final db = await DbHelper.instance.database;
    final result = await db.delete(
      DbConstants.tableSongs,
      where: 'sourceId = ?',
      whereArgs: [sourceId],
    );
    _cachedAll = null;
    CacheVersionStore.instance.bump(cacheVersionScope);
    return result;
  }
}
