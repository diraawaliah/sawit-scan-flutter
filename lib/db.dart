import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef DbRow = Map<String, Object?>;

/// Label efektif: koreksi pengguna jika ada, jika tidak hasil model.
String effLabel(DbRow r) => (r['corrected'] ?? r['label']) as String;

class AppDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'sawit.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (d, v) => d.execute('''
        CREATE TABLE scans(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT,
          label TEXT,
          confidence REAL,
          block TEXT,
          lat REAL,
          lng REAL,
          created TEXT,
          corrected TEXT,
          model TEXT
        )'''),
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          try {
            await d.execute('ALTER TABLE scans ADD COLUMN model TEXT');
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  static Future<int> insert(DbRow m) async => (await db).insert('scans', m);

  static Future<List<DbRow>> all() async =>
      (await db).query('scans', orderBy: 'id DESC');

  static Future<void> correct(int id, String label) async => (await db)
      .update('scans', {'corrected': label}, where: 'id = ?', whereArgs: [id]);

  static Future<void> remove(int id) async =>
      (await db).delete('scans', where: 'id = ?', whereArgs: [id]);

  static Future<void> clearAll() async => (await db).delete('scans');
}