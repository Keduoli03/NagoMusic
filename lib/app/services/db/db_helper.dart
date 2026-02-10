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
      },
    );
  }
}
