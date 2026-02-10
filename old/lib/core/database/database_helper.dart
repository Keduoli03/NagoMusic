import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../models/music_entity.dart';
import '../../models/playlist_model.dart';

List<MusicEntity> _parseMusicEntities(List<Map<String, dynamic>> maps) {
  return List.generate(maps.length, (i) {
    // Create a mutable copy to adjust types
    final map = Map<String, dynamic>.from(maps[i]);
    // isLocal 1 -> true
    map['isLocal'] = map['isLocal'] == 1;
    // headers: we removed them, so they are null. 
    // LibraryViewModel re-attaches auth headers for WebDAV.
    return MusicEntity.fromJson(map);
  });
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vibe_music.db');

    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE songs(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        uri TEXT,
        isLocal INTEGER,
        durationMs INTEGER,
        sourceId TEXT,
        localCoverPath TEXT,
        localLyricPath TEXT,
        headers TEXT,
        lyrics TEXT,
        fileModifiedMs INTEGER,
        tagsParsed INTEGER,
        fileSize INTEGER,
        bitrate INTEGER,
        sampleRate INTEGER,
        format TEXT
      )
    ''');
    await _createPlaylistTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE songs ADD COLUMN lyrics TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE songs ADD COLUMN fileModifiedMs INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE songs ADD COLUMN tagsParsed INTEGER');
    }
    if (oldVersion < 5) {
      await _createPlaylistTables(db);
    }
    if (oldVersion < 6) {
      // Ensure tables and default playlist exist (idempotent)
      await _createPlaylistTables(db);
    }
    if (oldVersion < 7) {
      // Add sort_order to playlists
      try {
        await db.execute('ALTER TABLE playlists ADD COLUMN sort_order INTEGER DEFAULT 0');
      } catch (_) {
        // Ignore if already exists
      }
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE songs ADD COLUMN fileSize INTEGER');
      await db.execute('ALTER TABLE songs ADD COLUMN bitrate INTEGER');
      await db.execute('ALTER TABLE songs ADD COLUMN sampleRate INTEGER');
      await db.execute('ALTER TABLE songs ADD COLUMN format TEXT');
    }
  }

  Future<void> _createPlaylistTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER,
        is_favorite INTEGER,
        sort_order INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs(
        playlist_id INTEGER,
        song_id TEXT,
        added_at INTEGER,
        PRIMARY KEY (playlist_id, song_id)
      )
    ''');
    // Create default 'My Favorites' playlist
    final result = await db.query(
      'playlists',
      where: 'is_favorite = ?',
      whereArgs: [1],
    );
    if (result.isEmpty) {
      await db.insert('playlists', {
        'name': '我喜欢',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_favorite': 1,
        'sort_order': 0,
      });
    }
  }

  Future<void> updateMusic(MusicEntity song) async {
    final db = await database;
    final map = song.toJson();
    map['isLocal'] = song.isLocal ? 1 : 0;
    map['tagsParsed'] = song.tagsParsed ? 1 : 0;
    map.remove('headers');

    await db.update(
      'songs',
      map,
      where: 'id = ?',
      whereArgs: [song.id],
    );
  }

  Future<void> insertSong(MusicEntity song) async {
    final db = await database;
    final map = song.toJson();
    map['isLocal'] = song.isLocal ? 1 : 0;
    map.remove('artwork'); 
    map.remove('headers'); 
    
    await db.insert(
      'songs',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSongs(List<MusicEntity> songs) async {
    final db = await database;
    final batch = db.batch();
    for (final song in songs) {
      final map = song.toJson();
      map['isLocal'] = song.isLocal ? 1 : 0;
      map.remove('artwork');
      map.remove('headers');
      batch.insert(
        'songs',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<MusicEntity>> getSongs() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('songs');
    return compute(_parseMusicEntities, maps);
  }

  Future<List<MusicEntity>> getLocalSongsInFolder(String folderPath) async {
    final db = await database;
    String prefix = folderPath;
    if (prefix.endsWith('/') || prefix.endsWith('\\')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'isLocal = 1 AND (uri LIKE ? OR uri LIKE ?)',
      whereArgs: ['$prefix/%', '$prefix\\%'],
    );

    return compute(_parseMusicEntities, maps);
  }

  Future<void> clearSongsBySource(String sourceId) async {
    final db = await database;
    await db.delete(
      'songs',
      where: 'sourceId = ?',
      whereArgs: [sourceId],
    );
  }

  Future<void> deleteSongsByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'songs',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> updateSongCover(String id, String path) async {
    final db = await database;
    await db.update(
      'songs',
      {'localCoverPath': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<MusicEntity?> getSongById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'songs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final map = Map<String, dynamic>.from(maps.first);
      map['isLocal'] = map['isLocal'] == 1;
      return MusicEntity.fromJson(map);
    }
    return null;
  }

  Future<List<MusicEntity>> getSongsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final maps = await db.query(
      'songs',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    final byId = <String, MusicEntity>{};
    for (final raw in maps) {
      final map = Map<String, dynamic>.from(raw);
      map['isLocal'] = map['isLocal'] == 1;
      final song = MusicEntity.fromJson(map);
      byId[song.id] = song;
    }
    final result = <MusicEntity>[];
    for (final id in ids) {
      final song = byId[id];
      if (song != null) {
        result.add(song);
      }
    }
    return result;
  }

  Future<void> updateSongCoverPath(String id, String path) async {
    final db = await database;
    await db.update(
      'songs',
      {'localCoverPath': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getLyricsCacheSize() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(LENGTH(lyrics)) AS total FROM songs WHERE lyrics IS NOT NULL',
    );
    final raw = result.isNotEmpty ? result.first['total'] : null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> clearLyricsCache() async {
    final db = await database;
    await db.update(
      'songs',
      {'lyrics': null, 'localLyricPath': null},
    );
  }

  // Playlist Methods

  Future<int> createPlaylist(String name) async {
    final db = await database;
    final maxRes = await db.rawQuery('SELECT MAX(sort_order) as max_order FROM playlists');
    int maxOrder = 0;
    if (maxRes.isNotEmpty && maxRes.first['max_order'] != null) {
      maxOrder = maxRes.first['max_order'] as int;
    }

    return await db.insert('playlists', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_favorite': 0,
      'sort_order': maxOrder + 1,
    });
  }

  Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.*, COUNT(ps.song_id) as song_count
      FROM playlists p
      LEFT JOIN playlist_songs ps ON p.id = ps.playlist_id
      GROUP BY p.id
      ORDER BY p.is_favorite DESC, p.sort_order ASC, p.created_at DESC
    ''');

    return List.generate(result.length, (i) {
      return Playlist.fromJson(result[i]);
    });
  }

  Future<void> renamePlaylist(int id, String newName) async {
    final db = await database;
    await db.update(
      'playlists',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePlaylistOrder(List<int> playlistIds) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < playlistIds.length; i++) {
      batch.update(
        'playlists',
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [playlistIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deletePlaylist(int id) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    await db.delete('playlist_songs', where: 'playlist_id = ?', whereArgs: [id]);
  }

  Future<void> addSongToPlaylist(int playlistId, String songId) async {
    final db = await database;
    await db.insert(
      'playlist_songs',
      {
        'playlist_id': playlistId,
        'song_id': songId,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addSongsToPlaylist(int playlistId, List<String> songIds) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < songIds.length; i++) {
      batch.insert(
        'playlist_songs',
        {
          'playlist_id': playlistId,
          'song_id': songIds[i],
          'added_at': now - i,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeSongFromPlaylist(int playlistId, String songId) async {
    final db = await database;
    await db.delete(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
  }

  Future<List<String>> getSongIdsInPlaylist(int playlistId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'playlist_songs',
      columns: ['song_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at DESC',
    );
    return maps.map((m) => m['song_id'] as String).toList();
  }

  Future<bool> isSongInPlaylist(int playlistId, String songId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<void> updatePlaylistSongOrder(int playlistId, List<String> songIds) async {
    final db = await database;
    final batch = db.batch();
    final baseTime = DateTime.now().millisecondsSinceEpoch;
    
    for (int i = 0; i < songIds.length; i++) {
      final songId = songIds[i];
      final newTime = baseTime - (i * 1000);
      batch.update(
        'playlist_songs',
        {'added_at': newTime},
        where: 'playlist_id = ? AND song_id = ?',
        whereArgs: [playlistId, songId],
      );
    }
    await batch.commit(noResult: true);
  }
}
