import 'offline_queue_storage.dart';

// Persisted queue of not-yet-synced runner events (scan/position/sos/app_event) - the "offline-
// first obligatoire" requirement (design/design_campus_manager/README.md's e-CO section): every
// write survives an app kill/zone-blanche gap and is replayed once QueueProcessor sees the
// network come back, in the order it was recorded (important for scans - see that class).
//
// Where it is kept depends on the platform (offline_queue_storage.dart): a SQLite table on the
// phone, IndexedDB in the browser - the PWA, whose service worker can then send what is left when
// the page itself no longer runs (web/eco_queue.js).
class QueuedItem {
  final int id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  QueuedItem({required this.id, required this.type, required this.payload, required this.createdAt});
}

class OfflineQueueDb {
  final OfflineQueueStorage _storage = OfflineQueueStorage();

  /// The runner the items are recorded for, set by QueueProcessor when a race screen opens. Only
  /// the web keeps it, on each item: its service worker sends them without the page, so it has no
  /// session to ask. The phone sends with the session's token and ignores it.
  String? runnerToken;

  Future<void> enqueue(String type, Map<String, dynamic> payload) => _storage.enqueue(type, payload, runnerToken);

  Future<List<QueuedItem>> pending({String? type}) => _storage.pending(type: type);

  Future<void> remove(int id) => _storage.remove(id);

  Future<int> count() => _storage.count();

  /// Runs one pass of sending. In the browser the service worker may be sending the same queue at
  /// that moment (background sync): one pass at a time, or both would post the same items.
  Future<void> exclusive(Future<void> Function() pass) => _storage.exclusive(pass);
}
