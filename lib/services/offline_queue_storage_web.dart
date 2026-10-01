import 'dart:convert';
import 'dart:js_interop';

import 'offline_queue_db.dart';

// web/eco_queue.js, loaded by index.html before the app and imported by the service worker: the
// queue lives in IndexedDB, behind that one script, so the page and the service worker read and
// write it the same way.
@JS('ecoQueue')
external _EcoQueue get _ecoQueue;

extension type _EcoQueue._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> enqueue(String type, String payload, String? token);
  external JSPromise<JSString> pending(String? type);
  external JSPromise<JSAny?> remove(int id);
  external JSPromise<JSNumber> count();
  external JSPromise<JSAny?> exclusive(JSFunction pass);
  external void syncIfPending();
}

class OfflineQueueStorage {
  /// [runnerToken] is stamped on the item: the service worker sends it without the page.
  Future<void> enqueue(String type, Map<String, dynamic> payload, String? runnerToken) async {
    await _ecoQueue.enqueue(type, jsonEncode(payload), runnerToken).toDart;
  }

  Future<List<QueuedItem>> pending({String? type}) async {
    final json = (await _ecoQueue.pending(type).toDart).toDart;
    return (jsonDecode(json) as List<dynamic>).cast<Map<String, dynamic>>().map((row) {
      return QueuedItem(
        id: (row['id'] as num).toInt(),
        type: row['type'] as String,
        payload: row['payload'] as Map<String, dynamic>,
        createdAt: DateTime.parse(row['createdAt'] as String),
      );
    }).toList();
  }

  Future<void> remove(int id) async {
    await _ecoQueue.remove(id).toDart;
  }

  Future<int> count() async => (await _ecoQueue.count().toDart).toDartInt;

  /// Under the same Web Lock as the service worker's pass. Whatever the pass could not send is then
  /// handed to background sync: the browser will try again once the network is back, even with
  /// the page frozen behind a locked screen (Chrome on Android; Safari has no background sync).
  Future<void> exclusive(Future<void> Function() pass) async {
    await _ecoQueue.exclusive((() => pass().toJS).toJS).toDart;
    _ecoQueue.syncIfPending();
  }
}
