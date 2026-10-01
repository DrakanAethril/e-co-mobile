import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_client.dart';
import 'offline_queue_db.dart';

// Drains OfflineQueueDb whenever connectivity comes back (and on a periodic timer as a fallback,
// in case the connectivity plugin misses a transition) - each item is retried until it succeeds;
// a network failure mid-drain just stops that pass, nothing is lost, the next trigger retries
// from the same point (items are only removed after a confirmed server response).
//
// A confirmed response includes a refusal (ApiException.isRefusal): the server has answered, and
// would answer the same thing every time - an unknown checkpoint code, a token it does not know.
// Such an item is removed and reported (onRejected) rather than retried: kept, it stood at the
// head of its queue for ever, and a mistyped code held back every scan after it, the finish
// included.
//
// The PWA runs this same class; its service worker adds a second sender for when the page is
// frozen (web/eco_sw.js), which is why a pass runs under OfflineQueueDb.exclusive() - and why
// web/eco_queue.js repeats these rules.
class QueueProcessor {
  /// Positions per call: a long dead zone queues hundreds of them, and one oversized request
  /// refused would otherwise be all of them.
  static const positionBatchSize = 200;

  final ApiClient _api;
  final OfflineQueueDb _queue;
  final String Function() _tokenProvider;

  /// An item the server refused, removed from the queue - the race screen says so for a scan.
  final void Function(QueuedItem item, ApiException refusal)? onRejected;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _fallbackTimer;
  bool _flushing = false;

  QueueProcessor(this._api, this._queue, this._tokenProvider, {this.onRejected});

  void start() {
    _queue.runnerToken = _tokenProvider();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        flush();
      }
    });
    _fallbackTimer = Timer.periodic(const Duration(seconds: 15), (_) => flush());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _fallbackTimer?.cancel();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _queue.exclusive(() async {
        await _flushPositions();
        await _flushSequential('scan');
        await _flushSequential('sos');
        await _flushSequential('app_event');
      });
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushPositions() async {
    final items = await _queue.pending(type: 'position');

    for (var start = 0; start < items.length; start += positionBatchSize) {
      final batch = items.sublist(start, start + positionBatchSize > items.length ? items.length : start + positionBatchSize);
      try {
        await _api.runnerPositions(_tokenProvider(), batch.map((i) => i.payload).toList());
      } on ApiException catch (e) {
        if (!e.isRefusal) return;
        // Refused for good: dropped like a sent batch, they would be refused again.
      } catch (_) {
        return; // Network still down - leave everything queued for the next trigger.
      }
      for (final item in batch) {
        await _queue.remove(item.id);
      }
    }
  }

  Future<void> _flushSequential(String type) async {
    final items = await _queue.pending(type: type);
    for (final item in items) {
      try {
        switch (type) {
          case 'scan':
            await _api.runnerScan(
              _tokenProvider(),
              item.payload['code'] as String,
              (item.payload['latitude'] as num?)?.toDouble(),
              (item.payload['longitude'] as num?)?.toDouble(),
              method: item.payload['method'] as String? ?? 'qr_scan',
              // Absent from a scan queued by an app older than 1.3.3: the server then dates it
              // on arrival, as it always did.
              scannedAt: item.payload['scannedAt'] as String?,
            );
          case 'sos':
            await _api.runnerSos(_tokenProvider());
          case 'app_event':
            // `at` is absent from an event queued by an older app: dated on arrival, as before.
            await _api.runnerAppEvent(_tokenProvider(), item.payload['type'] as String, at: item.payload['at'] as String?);
        }
      } on ApiException catch (e) {
        if (!e.isRefusal) return; // stop this pass, preserve order for the retry
        await _queue.remove(item.id);
        onRejected?.call(item, e);
        continue;
      } catch (_) {
        return; // stop this pass, preserve order for the retry
      }
      await _queue.remove(item.id);
    }
  }
}
