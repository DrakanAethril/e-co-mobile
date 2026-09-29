import 'package:eco/screens/teacher_parcours_edit_screen.dart';
import 'package:eco/screens/teacher_parcours_terrain_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A parcours' two pages in the teacher app, against an in-memory server: the radius of each flag
/// edited and saved, and the IGN's reading of the ground, asked for then read once written.
class _FakeApi extends ApiClient {
  final tolerances = <int, int>{1: 20, 2: 20, 3: 20};
  Map<String, int>? saved;
  bool analysed = false;
  int terrainReads = 0;

  Map<String, dynamic> _checkpoint(int id, String type, int position, String name, {int? advised, double? canopy}) => {
        'id': id,
        'name': name,
        'note': null,
        'shortCode': 'K7PX2M$id',
        'position': position,
        'type': type,
        'toleranceMeters': tolerances[id],
        'located': true,
        'latitude': 45.83,
        'longitude': 1.26,
        'locatedAt': '2026-09-28T10:00:00+02:00',
        'groundAltitude': 312.0,
        'canopyHeight': canopy,
        'advisedToleranceMeters': advised,
      };

  Map<String, dynamic> _parcours() => {
        'id': 7,
        'name': 'Bois de la Bastide',
        'ready': true,
        'defaultToleranceMeters': 20,
        'checkpoints': [
          _checkpoint(1, 'start', 0, 'Départ'),
          _checkpoint(2, 'checkpoint', 1, 'Balise 1', advised: tolerances[2]! < 30 ? 30 : null, canopy: 18),
          _checkpoint(3, 'finish', 2, 'Arrivée'),
        ],
      };

  @override
  Future<Map<String, dynamic>> teacherParcoursShow(int id) async => _parcours();

  @override
  Future<Map<String, dynamic>> teacherSaveTolerances(int parcoursId, Map<String, int> values) async {
    saved = values;
    values.forEach((id, meters) => tolerances[int.parse(id)] = meters);
    return _parcours();
  }

  Map<String, dynamic> _sheet({required bool pending}) => {
        'pending': pending,
        'canAnalyze': !pending,
        'analyzedAt': analysed ? '2026-09-28T10:05:00+02:00' : null,
        'current': analysed,
        'flags': [
          {'id': 1, 'label': 'D', 'type': 'start', 'name': 'Départ', 'latitude': 45.830, 'longitude': 1.260},
          {'id': 2, 'label': '1', 'type': 'checkpoint', 'name': 'Balise 1', 'latitude': 45.832, 'longitude': 1.263},
          {'id': 3, 'label': 'A', 'type': 'finish', 'name': 'Arrivée', 'latitude': 45.831, 'longitude': 1.259},
        ],
        'analysis': analysed
            ? {
                'commune': 'Limoges',
                'nearbyPlace': 'Le Mas Éloi',
                'publicForests': ['Forêt domaniale des Vaseix'],
                'incomplete': false,
                'legs': [
                  {
                    'fromLabel': 'D', 'toLabel': '1', 'straightMeters': 111.2, 'pathMeters': 260.0, 'pathRatio': 2.3,
                    'climbMeters': 6.0, 'descentMeters': 2.0, 'maxSlopePercent': 32.0, 'forestShare': 0.4, 'effortKm': 0.17,
                  },
                ],
                'checkpoints': [
                  {'id': 1, 'label': 'D', 'name': 'Départ', 'groundAltitude': 312.4, 'canopyHeight': 18.0, 'nearestCarRoadMeters': 620.0, 'nearestWaterMeters': null, 'publicForest': null},
                ],
              }
            : null,
      };

  @override
  Future<Map<String, dynamic>> teacherParcoursTerrain(int parcoursId) async {
    terrainReads++;
    // The scheduled read writes the analysis between two polls.
    if (terrainReads > 1) analysed = true;
    return _sheet(pending: false);
  }

  @override
  Future<Map<String, dynamic>> teacherRequestTerrain(int parcoursId) async => _sheet(pending: true);
}

Future<void> _open(WidgetTester tester, _FakeApi api, Widget screen) async {
  await tester.pumpWidget(
    Provider<ApiClient>.value(value: api, child: MaterialApp(theme: ecoTheme(), home: screen)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(disableEcoFontFetching);
  // The map remembers its layers on the phone.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the radius of each flag is edited, the advice filled in one tap, then saved', (tester) async {
    final api = _FakeApi();
    await _open(tester, api, const TeacherParcoursEditScreen(parcoursId: 7, parcoursName: 'Bois de la Bastide'));

    expect(find.text('K7PX2M2'), findsOneWidget);
    await tester.tap(find.text('Conseillé : 30 m'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('tolerance-3')), '15');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(api.saved, {'1': 20, '2': 30, '3': 15});
    expect(find.text('Parcours enregistré.'), findsOneWidget);
    // Now wide enough: the advice is gone.
    expect(find.text('Conseillé : 30 m'), findsNothing);
  });

  testWidgets('the ground is asked for, then read once the server has written it', (tester) async {
    final api = _FakeApi();
    await _open(
      tester,
      api,
      const TeacherParcoursTerrainScreen(parcoursId: 7, parcoursName: 'Bois de la Bastide', pollInterval: Duration(milliseconds: 10)),
    );

    expect(find.textContaining('Pas encore analysé'), findsOneWidget);
    // The flags are on the map before any analysis: where they stand needs no IGN answer.
    expect(find.text('CARTE DU PARCOURS'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.tap(find.text('Analyser le terrain'));
    await tester.pump();
    expect(find.textContaining('Analyse en cours'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.textContaining('Analysé le 28/09/2026'), findsOneWidget);
    expect(find.text("Relancer l'analyse"), findsOneWidget);
    expect(find.textContaining('Limoges · près de « Le Mas Éloi »', findRichText: true), findsOneWidget);
    expect(find.textContaining('forêt publique'), findsOneWidget);
    // The map comes before the legs, its three flags labelled as the legs name them.
    expect(find.descendant(of: find.byType(MarkerLayer), matching: find.text('D')), findsOneWidget);
    expect(find.descendant(of: find.byType(MarkerLayer), matching: find.text('A')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('TRONÇONS'), 200);
    expect(tester.getBottomLeft(find.byType(FlutterMap)).dy, lessThan(tester.getTopLeft(find.text('TRONÇONS')).dy));
    expect(find.text('260 m (×2,3)'), findsOneWidget);
    expect(find.text('32 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('620 m'), 200);
    expect(find.text('620 m'), findsOneWidget);
  });
}
