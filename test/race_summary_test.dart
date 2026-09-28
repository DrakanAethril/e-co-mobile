import 'package:eco/screens/race_summary_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The recap a runner reads at the finish, against an in-memory server: the time, the figures,
/// the time of each leg - and a server out of reach says so rather than showing zeros.
class _FakeApi extends ApiClient {
  bool offline = false;
  String? askedToken;

  @override
  Future<Map<String, dynamic>> runnerSummary(String token) async {
    askedToken = token;
    if (offline) throw Exception('no network');

    return {
      'pseudo': 'lilou',
      'courseName': '2NDE B — mercredi',
      'parcoursName': 'Bois de la Bastide',
      'mode': 'imposed_order',
      'startedAt': '2026-09-28T10:00:00+02:00',
      'finishedAt': '2026-09-28T10:32:14+02:00',
      'durationSeconds': 1934,
      'distanceMeters': 2437,
      'averageSpeedKmh': 4.53,
      'elevationGain': 48,
      'elevationLoss': 45,
      'elevationSource': 'gps',
      'checkpointsValidated': 7,
      'checkpointsTotal': 8,
      'scanFailureCount': 1,
      'stopCount': 2,
      'stopSeconds': 150,
      'legs': [
        {'fromName': 'Départ', 'toName': 'Balise 1', 'seconds': 240, 'distanceMeters': 320},
        {'fromName': 'Balise 1', 'toName': 'Balise 2', 'seconds': 3725, 'distanceMeters': 1210},
      ],
    };
  }
}

Future<void> _open(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    Provider<ApiClient>.value(
      value: api,
      child: MaterialApp(theme: ecoTheme(), home: const RaceSummaryScreen(token: 'abc')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(disableEcoFontFetching);

  testWidgets('the recap shows the time, the figures and each leg', (tester) async {
    final api = _FakeApi();
    await _open(tester, api);

    expect(api.askedToken, 'abc');
    expect(find.text('Bravo, lilou !'), findsOneWidget);
    expect(find.text('32:14'), findsOneWidget);
    expect(find.text('2,4 km'), findsOneWidget);
    expect(find.text('4,5 km/h'), findsOneWidget);
    expect(find.text('7/8'), findsOneWidget);
    expect(find.text('+48 m'), findsOneWidget);
    expect(find.text('GPS du téléphone'), findsOneWidget);
    expect(find.text('2 · 3 min'), findsOneWidget);
    // The legs sit below the fold of the test surface.
    await tester.scrollUntilVisible(find.text('1:02:05'), 200);
    expect(find.text('Départ → Balise 1'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);
    // Past the hour the leg reads in hours.
    expect(find.text('1:02:05'), findsOneWidget);
  });

  testWidgets('out of network the recap says so and offers to try again', (tester) async {
    final api = _FakeApi()..offline = true;
    await _open(tester, api);

    expect(find.text('Récapitulatif indisponible hors réseau.'), findsOneWidget);

    api.offline = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('32:14'), findsOneWidget);
  });
}
