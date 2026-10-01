import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'offline_queue_db.dart';

class OfflineQueueStorage {
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

  /// [runnerToken] is not stored: the phone sends with the session's token.
  Future<void> enqueue(String type, Map<String, dynamic> payload, String? runnerToken) async {
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

  /// Nothing else sends this queue on the phone.
  Future<void> exclusive(Future<void> Function() pass) => pass();
}
