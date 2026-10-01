import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_client.dart';
import 'offline_queue_db.dart';

// Drains OfflineQueueDb whenever connectivity comes back (and on a periodic timer as a fallback,
// in case the connectivity plugin misses a transition) - each item is retried until it succeeds;
// a network failure mid-drain just stops that pass, nothing is lost, the next trigger retries
// from the same point (items are only removed after a confirmed server response).
//
// The PWA runs this same class; its service worker adds a second sender for when the page is
// frozen (web/eco_sw.js), which is why a pass runs under OfflineQueueDb.exclusive().
class QueueProcessor {
  final ApiClient _api;
  final OfflineQueueDb _queue;
  final String Function() _tokenProvider;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _fallbackTimer;
  bool _flushing = false;

  QueueProcessor(this._api, this._queue, this._tokenProvider);

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
    if (items.isEmpty) return;

    try {
      await _api.runnerPositions(_tokenProvider(), items.map((i) => i.payload).toList());
      for (final item in items) {
        await _queue.remove(item.id);
      }
    } catch (_) {
      // Network still down (or server error) - leave everything queued for the next trigger.
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
            await _api.runnerAppEvent(_tokenProvider(), item.payload['type'] as String);
        }
        await _queue.remove(item.id);
      } catch (_) {
        return; // stop this pass, preserve order for the retry
      }
    }
  }
}
