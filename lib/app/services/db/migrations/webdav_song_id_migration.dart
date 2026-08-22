import 'package:sqflite/sqflite.dart';

import '../db_constants.dart';
import '../../../utils/webdav_song_id.dart';

/// One-time migration (DB v10 -> v11).
///
/// WebDAV song ids used to be the raw href, which baked the server's host
/// into the id. That meant configuring a second address for the same
/// source (e.g. a LAN address at home and a remote-access tunnel while
/// away) made every song look "new" the moment scanning picked the other
/// address, orphaning favorites, play stats and playlist entries tied to
/// the old id.
///
/// This rewrites existing WebDAV song ids to the path-based scheme from
/// webdav_song_id.dart (endpoint-agnostic) and follows the rename through
/// song_stats and playlist_songs so nothing keyed by the old id is lost.
Future<void> migrateWebdavSongIdsToPathBased(Database db) async {
  final rows = await db.query(
    DbConstants.tableSongs,
    columns: ['id', 'sourceId'],
    where: "isLocal = 0 AND (id LIKE 'http://%' OR id LIKE 'https://%')",
  );
  if (rows.isEmpty) return;

  final renames = <String, String>{};
  for (final row in rows) {
    final oldId = (row['id'] as String?) ?? '';
    final sourceId = (row['sourceId'] as String?) ?? '';
    if (oldId.isEmpty || sourceId.isEmpty) continue;
    final newId = buildWebdavSongId(sourceId: sourceId, hrefOrUri: oldId);
    if (newId != oldId) {
      renames[oldId] = newId;
    }
  }
  if (renames.isEmpty) return;

  int asInt(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  await db.transaction((txn) async {
    for (final entry in renames.entries) {
      final oldId = entry.key;
      final newId = entry.value;

      // songs: if the target id is already taken (two old hrefs collapsing
      // onto the same path — e.g. a stale duplicate from a prior scan),
      // drop the old row instead of overwriting the surviving one.
      final songConflict = await txn.query(
        DbConstants.tableSongs,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [newId],
        limit: 1,
      );
      if (songConflict.isNotEmpty) {
        await txn.delete(
          DbConstants.tableSongs,
          where: 'id = ?',
          whereArgs: [oldId],
        );
      } else {
        await txn.update(
          DbConstants.tableSongs,
          {'id': newId},
          where: 'id = ?',
          whereArgs: [oldId],
        );
      }

      // song_stats: merge counters (sum ms/count, max lastPlayed) if the new
      // id already has stats, otherwise just rename.
      final oldStats = await txn.query(
        DbConstants.tableSongStats,
        where: 'songId = ?',
        whereArgs: [oldId],
        limit: 1,
      );
      if (oldStats.isNotEmpty) {
        final newStats = await txn.query(
          DbConstants.tableSongStats,
          where: 'songId = ?',
          whereArgs: [newId],
          limit: 1,
        );
        if (newStats.isNotEmpty) {
          final a = oldStats.first;
          final b = newStats.first;
          final lastA = asInt(a['lastPlayedMs']);
          final lastB = asInt(b['lastPlayedMs']);
          await txn.update(
            DbConstants.tableSongStats,
            {
              'listenMs': asInt(a['listenMs']) + asInt(b['listenMs']),
              'playCount': asInt(a['playCount']) + asInt(b['playCount']),
              'lastPlayedMs': lastA > lastB ? lastA : lastB,
            },
            where: 'songId = ?',
            whereArgs: [newId],
          );
          await txn.delete(
            DbConstants.tableSongStats,
            where: 'songId = ?',
            whereArgs: [oldId],
          );
        } else {
          await txn.update(
            DbConstants.tableSongStats,
            {'songId': newId},
            where: 'songId = ?',
            whereArgs: [oldId],
          );
        }
      }

      // playlist_songs: rename per playlist, dropping the old row where the
      // new (playlistId, songId) pair already exists (would violate the PK).
      final oldPlaylistRows = await txn.query(
        DbConstants.tablePlaylistSongs,
        columns: ['playlistId'],
        where: 'songId = ?',
        whereArgs: [oldId],
      );
      for (final row in oldPlaylistRows) {
        final playlistId = row['playlistId'] as String;
        final conflict = await txn.query(
          DbConstants.tablePlaylistSongs,
          where: 'playlistId = ? AND songId = ?',
          whereArgs: [playlistId, newId],
          limit: 1,
        );
        if (conflict.isNotEmpty) {
          await txn.delete(
            DbConstants.tablePlaylistSongs,
            where: 'playlistId = ? AND songId = ?',
            whereArgs: [playlistId, oldId],
          );
        } else {
          await txn.update(
            DbConstants.tablePlaylistSongs,
            {'songId': newId},
            where: 'playlistId = ? AND songId = ?',
            whereArgs: [playlistId, oldId],
          );
        }
      }
    }
  });
}
