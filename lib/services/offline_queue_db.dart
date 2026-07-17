import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Persisted queue of not-yet-synced runner events (scan/position/sos/app_event) - the "offline-
// first obligatoire" requirement (design/design_campus_manager/README.md's e-CO section): every
// write survives an app kill/zone-blanche gap and is replayed once QueueProcessor sees the
// network come back, in the order it was recorded (important for scans - see that class).
class QueuedItem {
  final int id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  QueuedItem({required this.id, required this.type, required this.payload, required this.createdAt});
}

class OfflineQueueDb {
  static Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'eco_offline_queue.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE queue_item (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)',
      ),
    );
    return _db!;
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    final db = await _database();
    await db.insert('queue_item', {
      'type': type,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<QueuedItem>> pending({String? type}) async {
    final db = await _database();
    final rows = await db.query(
      'queue_item',
      where: type != null ? 'type = ?' : null,
      whereArgs: type != null ? [type] : null,
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => QueuedItem(
              id: row['id'] as int,
              type: row['type'] as String,
              payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
              createdAt: DateTime.parse(row['created_at'] as String),
            ))
        .toList();
  }

  Future<void> remove(int id) async {
    final db = await _database();
    await db.delete('queue_item', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _database();
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM queue_item');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
