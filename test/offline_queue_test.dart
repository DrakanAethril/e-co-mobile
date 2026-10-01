import 'dart:convert';

import 'package:eco/models/runner_session.dart';
import 'package:eco/screens/join_screen.dart';
import 'package:eco/screens/race_screen.dart';
import 'package:eco/screens/splash_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/services/location_service.dart';
import 'package:eco/services/offline_queue_db.dart';
import 'package:eco/services/queue_processor.dart';
import 'package:eco/services/session_store.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The offline queue's three rules, the same on the phone and in the PWA (whose service worker
/// repeats them in web/eco_queue.js): a call the server refused for good leaves the queue instead
/// of blocking it, a relaunch without network goes on with the race, and an app event keeps the
/// time it happened.

/// The queue in memory - the platform storages are SQLite and IndexedDB, neither in a unit test.
class _MemoryQueue implements OfflineQueueDb {
  final items = <QueuedItem>[];
  int _nextId = 1;

  @override
  String? runnerToken;

  @override
  Future<void> enqueue(String type, Map<String, dynamic> payload) async =>
      items.add(QueuedItem(id: _nextId++, type: type, payload: payload, createdAt: DateTime.now()));

  @override
  Future<List<QueuedItem>> pending({String? type}) async => items.where((i) => type == null || i.type == type).toList();

  @override
  Future<void> remove(int id) async => items.removeWhere((i) => i.id == id);

  @override
  Future<int> count() async => items.length;

  @override
  Future<void> exclusive(Future<void> Function() pass) => pass();

  List<String> get codes => items.map((i) => i.payload['code'] as String? ?? i.type).toList();
}

/// moncampus's runner API: a scan of « BAD » is an unknown code, « BOOM » a server error.
class _Server {
  bool offline = false;
  int stateStatus = 200;
  final scans = <String>[];
  final positionCalls = <int>[];
  final events = <Map<String, dynamic>>[];

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;

    switch (request.url.path) {
      case '/api/eco/runner/scan':
        final code = body['code'] as String;
        if (code == 'BAD') return http.Response('{"error":"checkpointNotFound"}', 404);
        if (code == 'BOOM') return http.Response('<html>Bad Gateway</html>', 502);
        scans.add(code);
        return http.Response('{"result":"success","checkpointId":1,"runnerStatus":"racing"}', 200);
      case '/api/eco/runner/positions':
        positionCalls.add((body['points'] as List).length);
        return http.Response('{"success":true}', 200);
      case '/api/eco/runner/app-events':
        events.add(body);
        return http.Response('{"success":true}', 200);
      case '/api/eco/runner/state':
        if (stateStatus != 200) return http.Response('{"error":"invalidToken"}', stateStatus);
        return http.Response(jsonEncode(_session(parcoursName: 'Bois de la Bastide (serveur)')), 200);
    }

    return http.Response('', 404);
  });
}

Map<String, dynamic> _session({String parcoursName = 'Bois de la Bastide'}) => {
      'runnerId': 7,
      'token': 'tok',
      'pseudo': 'lilou',
      'status': 'not_started',
      'courseName': '2NDE B',
      'parcoursName': parcoursName,
      'mode': 'imposed_order',
      'mapVisibility': 'none',
      'timeLimitMinutes': null,
      'startedAt': null,
      'finishedAt': null,
      'validatedCheckpointIds': <int>[],
      'checkpoints': [
        {'id': 1, 'name': 'Départ', 'position': 0, 'type': 'start', 'toleranceMeters': 60},
        {'id': 2, 'name': 'Balise 1', 'position': 1, 'type': 'checkpoint', 'toleranceMeters': 60},
        {'id': 3, 'name': 'Arrivée', 'position': 2, 'type': 'finish', 'toleranceMeters': 60},
      ],
    };

Future<void> _scan(_MemoryQueue queue, String code) =>
    queue.enqueue('scan', {'code': code, 'method': 'manual_code', 'latitude': 45.8, 'longitude': 1.26, 'scannedAt': '2026-10-01T08:00:00.000Z'});

void main() {
  setUpAll(disableEcoFontFetching);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('the queue', () {
    test('a scan the server refuses leaves the queue and is reported; the ones after it are sent', () async {
      final server = _Server();
      final queue = _MemoryQueue();
      final rejected = <String>[];
      final processor = QueueProcessor(ApiClient(), queue, () => 'tok',
          onRejected: (item, refusal) => rejected.add('${item.payload['code']}:${refusal.error}'));
      await _scan(queue, 'BAD');
      await _scan(queue, 'ARR');

      await http.runWithClient(processor.flush, () => server.client);

      expect(rejected, ['BAD:checkpointNotFound']);
      expect(server.scans, ['ARR']);
      expect(queue.items, isEmpty);
    });

    test('without network, or with a server in error, everything stays queued in order', () async {
      final server = _Server()..offline = true;
      final queue = _MemoryQueue();
      final processor = QueueProcessor(ApiClient(), queue, () => 'tok');
      await _scan(queue, 'DEP');
      await _scan(queue, 'B1');

      await http.runWithClient(processor.flush, () => server.client);
      expect(queue.codes, ['DEP', 'B1']);

      server.offline = false;
      await _scan(queue, 'BOOM');
      queue.items.insert(0, queue.items.removeLast());
      await http.runWithClient(processor.flush, () => server.client);

      // A 502 is not an answer about the scan: it waits, and so does what follows it.
      expect(queue.codes, ['BOOM', 'DEP', 'B1']);
      expect(server.scans, isEmpty);
    });

    test('positions go in batches, so a long dead zone is never one oversized call', () async {
      final server = _Server();
      final queue = _MemoryQueue();
      for (var i = 0; i < 450; i++) {
        await queue.enqueue('position', {'latitude': 45.8, 'longitude': 1.26, 'recordedAt': '2026-10-01T08:00:00.000Z'});
      }

      await http.runWithClient(QueueProcessor(ApiClient(), queue, () => 'tok').flush, () => server.client);

      expect(server.positionCalls, [200, 200, 50]);
      expect(queue.items, isEmpty);
    });

    test('an app event is sent with the time it happened, an older one without', () async {
      final server = _Server();
      final queue = _MemoryQueue();
      await queue.enqueue('app_event', {'type': 'left', 'at': '2026-10-01T08:10:00.000Z'});
      await queue.enqueue('app_event', {'type': 'returned'});

      await http.runWithClient(QueueProcessor(ApiClient(), queue, () => 'tok').flush, () => server.client);

      expect(server.events, [
        {'token': 'tok', 'type': 'left', 'at': '2026-10-01T08:10:00.000Z'},
        {'token': 'tok', 'type': 'returned'},
      ]);
    });
  });

  group('a relaunch', () {
    setUp(() {
      // QueueProcessor listens to connectivity; there is no plugin in a test.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(onListen: (_, __) {}),
      );
    });

    Future<_MemoryQueue> launch(WidgetTester tester, _Server server) async {
      final queue = _MemoryQueue();
      await http.runWithClient(() async {
        await tester.pumpWidget(MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: ApiClient(sessionStore: SessionStore())),
            Provider<SessionStore>.value(value: SessionStore()),
            Provider<OfflineQueueDb>.value(value: queue),
            Provider<LocationService>.value(value: LocationService(queue)),
          ],
          child: MaterialApp(theme: ecoTheme(), home: const SplashScreen()),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle(const Duration(milliseconds: 50));
      }, () => server.client);

      return queue;
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('without network, the race goes on from the last state kept', (tester) async {
      await SessionStore().saveRunnerToken('tok', 'lilou');
      await SessionStore().saveRunnerSnapshot(RunnerSession.fromJson(_session()).toJson());

      await launch(tester, _Server()..offline = true);

      expect(find.byType(RaceScreen), findsOneWidget);
      expect(find.textContaining('Bois de la Bastide'), findsOneWidget);
      expect(await SessionStore().loadRunnerToken(), 'tok');
      await leave(tester);
    });

    testWidgets('reopening a race under way tells the server the runner is back in the app', (tester) async {
      await SessionStore().saveRunnerToken('tok', 'lilou');
      final racing = _session()
        ..['status'] = 'racing'
        ..['startedAt'] = '2026-10-01T08:00:00.000Z';
      await SessionStore().saveRunnerSnapshot(racing);

      final queue = await launch(tester, _Server()..offline = true);

      final events = queue.items.where((i) => i.type == 'app_event').toList();
      expect(events.map((i) => i.payload['type']), ['returned']);
      expect(events.single.payload['at'], isNotNull);
      await leave(tester);
    });

    testWidgets('with network, the server state wins over the one kept', (tester) async {
      await SessionStore().saveRunnerToken('tok', 'lilou');
      await SessionStore().saveRunnerSnapshot(RunnerSession.fromJson(_session()).toJson());

      await launch(tester, _Server());

      expect(find.textContaining('(serveur)'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a runner the server no longer knows is signed out', (tester) async {
      await SessionStore().saveRunnerToken('tok', 'lilou');
      await SessionStore().saveRunnerSnapshot(RunnerSession.fromJson(_session()).toJson());

      await launch(tester, _Server()..stateStatus = 401);

      expect(find.byType(JoinScreen), findsOneWidget);
      expect(await SessionStore().loadRunnerToken(), isNull);
      expect(await SessionStore().loadRunnerSnapshot('tok'), isNull);
    });
  });
}
