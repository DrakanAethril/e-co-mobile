// The phone keeps the queue in SQLite, the browser in IndexedDB - sqflite has no web
// implementation, and the service worker of the PWA must be able to read what the page wrote.
export 'offline_queue_storage_sqflite.dart' if (dart.library.js_interop) 'offline_queue_storage_web.dart';
