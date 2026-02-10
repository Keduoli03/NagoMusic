import 'package:sqflite/sqflite.dart';

import '../db_constants.dart';
import '../db_helper.dart';
import '../../../state/song_state.dart';

class SongDao {
  static List<SongEntity>? _cachedAll;
  static Future<List<SongEntity>>? _cachedAllFuture;

  Future<int> upsertSongs(List<SongEntity> songs) async {
    if (songs.isEmpty) return 0;
    final db = await DbHelper.instance.database;
    final added = await db.transaction<int>((txn) async {
      var added = 0;
      final insertBatch = txn.batch();
      for (final song in songs) {
        insertBatch.insert(
          DbConstants.tableSongs,
          song.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final insertResults = await insertBatch.commit();
      for (final result in insertResults) {
        if (result is int && result > 0) {
          added += 1;
        }
      }

      final updateBatch = txn.batch();
      for (final song in songs) {
        updateBatch.insert(
          DbConstants.tableSongs,
          song.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await updateBatch.commit(noResult: true);
      return added;
    });
    _cachedAll = null;
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
    final result =
        await db.rawQuery('SELECT COUNT(*) as total FROM ${DbConstants.tableSongs}');
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
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      DbConstants.tableSongs,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final map = <String, SongEntity>{};
    for (final row in rows) {
      final song = SongEntity.fromMap(row);
      map[song.id] = song;
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
    return rows
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
  }

  Future<int> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final db = await DbHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final result = await db.delete(
      DbConstants.tableSongs,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    _cachedAll = null;
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
    return result;
  }
}
