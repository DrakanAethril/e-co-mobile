import 'dart:async';
import 'package:geolocator/geolocator.dart';

import 'offline_queue_db.dart';

// GPS every 5s while racing (design's own spec) - each fix is queued immediately (offline-first:
// see OfflineQueueDb/QueueProcessor), not held in memory, so a crash between two ticks loses at
// most the single in-flight sample, never the whole trace.
class LocationService {
  final OfflineQueueDb _queue;
  Timer? _timer;

  LocationService(this._queue);

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  void startTracking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    _tick();
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _queue.enqueue('position', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        // Altitude en mètres. Certains appareils n'en donnent pas et renvoient 0 : le serveur
        // accepte l'absence du champ, autant ne rien envoyer plutôt qu'un zéro qui ferait croire
        // à un parcours au niveau de la mer.
        if (position.altitude != 0) 'altitude': position.altitude,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // No fix available this tick (e.g. briefly no GPS lock) - just skip it, the next tick tries again.
    }
  }

  Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }
}
