import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'db_constants.dart';

class DbHelper {
  DbHelper._internal();

  static final DbHelper instance = DbHelper._internal();

  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    _db = await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, DbConstants.dbName);
    return openDatabase(
      path,
      version: DbConstants.dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE ${DbConstants.tableSongs} (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT,
  uri TEXT,
  isLocal INTEGER NOT NULL,
  headersJson TEXT,
  durationMs INTEGER,
  bitrate INTEGER,
  sampleRate INTEGER,
  fileSize INTEGER,
  format TEXT,
  sourceId TEXT,
  fileModifiedMs INTEGER,
  localCoverPath TEXT,
  tagsParsed INTEGER
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_title ON ${DbConstants.tableSongs}(title COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_artist ON ${DbConstants.tableSongs}(artist COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_album ON ${DbConstants.tableSongs}(album COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_source ON ${DbConstants.tableSongs}(sourceId)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_songs_source_title ON ${DbConstants.tableSongs}(sourceId, title COLLATE NOCASE)',
        );
        await db.execute('''
CREATE TABLE ${DbConstants.tablePlaylists} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  createdAtMs INTEGER NOT NULL,
  isFavorite INTEGER NOT NULL,
  sortOrder INTEGER NOT NULL
)
''');
        await db.execute('''
CREATE TABLE ${DbConstants.tablePlaylistSongs} (
  playlistId TEXT NOT NULL,
  songId TEXT NOT NULL,
  sortOrder INTEGER NOT NULL,
  PRIMARY KEY (playlistId, songId)
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist ON ${DbConstants.tablePlaylistSongs}(playlistId, sortOrder)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_playlist_songs_song ON ${DbConstants.tablePlaylistSongs}(songId)',
        );
        await db.execute('''
CREATE TABLE ${DbConstants.tableListeningDays} (
  dayKey TEXT PRIMARY KEY,
  listenMs INTEGER NOT NULL,
  playCount INTEGER NOT NULL
)
''');
        await db.execute('''
CREATE TABLE ${DbConstants.tableSongStats} (
  songId TEXT PRIMARY KEY,
  listenMs INTEGER NOT NULL,
  playCount INTEGER NOT NULL,
  lastPlayedMs INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_song_stats_playcount ON ${DbConstants.tableSongStats}(playCount)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN localCoverPath TEXT',
          );
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN tagsParsed INTEGER',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN bitrate INTEGER',
          );
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN sampleRate INTEGER',
          );
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN fileSize INTEGER',
          );
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN format TEXT',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE ${DbConstants.tableSongs} ADD COLUMN headersJson TEXT',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_songs_title ON ${DbConstants.tableSongs}(title COLLATE NOCASE)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_songs_artist ON ${DbConstants.tableSongs}(artist COLLATE NOCASE)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_songs_album ON ${DbConstants.tableSongs}(album COLLATE NOCASE)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_songs_source ON ${DbConstants.tableSongs}(sourceId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_songs_source_title ON ${DbConstants.tableSongs}(sourceId, title COLLATE NOCASE)',
          );
        }
        if (oldVersion < 6) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbConstants.tablePlaylists} (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  createdAtMs INTEGER NOT NULL,
  isFavorite INTEGER NOT NULL,
  sortOrder INTEGER NOT NULL
)
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbConstants.tablePlaylistSongs} (
  playlistId TEXT NOT NULL,
  songId TEXT NOT NULL,
  sortOrder INTEGER NOT NULL,
  PRIMARY KEY (playlistId, songId)
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist ON ${DbConstants.tablePlaylistSongs}(playlistId, sortOrder)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_playlist_songs_song ON ${DbConstants.tablePlaylistSongs}(songId)',
          );
        }
        if (oldVersion < 7) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbConstants.tableListeningDays} (
  dayKey TEXT PRIMARY KEY,
  listenMs INTEGER NOT NULL,
  playCount INTEGER NOT NULL
)
''');
          await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbConstants.tableSongStats} (
  songId TEXT PRIMARY KEY,
  listenMs INTEGER NOT NULL,
  playCount INTEGER NOT NULL,
  lastPlayedMs INTEGER NOT NULL
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_song_stats_playcount ON ${DbConstants.tableSongStats}(playCount)',
          );
        }
      },
    );
  }
}
