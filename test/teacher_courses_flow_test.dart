import 'package:eco/screens/teacher_home_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The teacher's course cycle from the phone, against an in-memory server: a ready parcours is
/// listed, a course is created on it, started, then stopped - and « En cours » follows along.
class _FakeApi extends ApiClient {
  final courses = <Map<String, dynamic>>[];
  Map<String, dynamic>? lastCreated;

  Map<String, dynamic> _course(int id, String name, String status) => {
        'id': id,
        'name': name,
        'code': 'K7PX2M',
        'parcoursId': 7,
        'parcoursName': 'Bois de la Bastide',
        'status': status,
        'statusLabel': switch (status) { 'in_progress' => 'En cours', 'closed' => 'Clôturée', _ => 'Préparée' },
        'mode': 'imposed_order',
        'modeLabel': 'Ordre imposé',
        'timeLimitMinutes': null,
        'runnerCount': 0,
      };

  void _setStatus(int id, String status) {
    final index = courses.indexWhere((c) => c['id'] == id);
    courses[index] = _course(id, courses[index]['name'] as String, status);
  }

  @override
  Future<Map<String, dynamic>> teacherParcoursList(String jwt) async => {'parcours': []};

  @override
  Future<Map<String, dynamic>> teacherReadyParcoursList(String jwt) async => {
        'parcours': [
          {'id': 7, 'name': 'Bois de la Bastide', 'checkpointCount': 8, 'preparedCount': 0, 'inProgressCount': 0, 'closedCount': 0},
        ],
      };

  @override
  Future<Map<String, dynamic>> teacherParcoursCourses(String jwt, int parcoursId) async => {
        'parcours': {'id': 7, 'name': 'Bois de la Bastide'},
        'courses': List.of(courses),
        'options': {
          'modes': [
            {'value': 'imposed_order', 'label': 'Ordre imposé', 'description': 'balises dans l’ordre', 'timeLimited': false},
            {'value': 'score', 'label': 'Course au score', 'description': 'points par balise', 'timeLimited': true},
          ],
          'mapVisibilities': [
            {'value': 'all_checkpoints', 'label': 'Toutes les balises'},
          ],
        },
      };

  @override
  Future<Map<String, dynamic>> teacherCreateCourse(String jwt, int parcoursId, Map<String, dynamic> course) async {
    lastCreated = course;
    final created = _course(courses.length + 1, course['name'] as String, 'prepared');
    courses.insert(0, created);
    return {'course': created};
  }

  @override
  Future<Map<String, dynamic>> teacherStartCourse(String jwt, int courseId) async {
    _setStatus(courseId, 'in_progress');
    return {'course': courses.firstWhere((c) => c['id'] == courseId)};
  }

  @override
  Future<Map<String, dynamic>> teacherCloseCourse(String jwt, int courseId) async {
    _setStatus(courseId, 'closed');
    return {'course': courses.firstWhere((c) => c['id'] == courseId)};
  }

  @override
  Future<Map<String, dynamic>> teacherCoursesInProgress(String jwt) async =>
      {'courses': courses.where((c) => c['status'] == 'in_progress').toList()};
}

void main() {
  setUpAll(disableEcoFontFetching);

  testWidgets('a course is created, started and stopped from the teacher menu', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: api,
        child: MaterialApp(theme: ecoTheme(), home: const TeacherHomeScreen(jwt: 'jwt')),
      ),
    );
    await tester.pumpAndSettle();

    // The menu: three tabs, « À localiser » first.
    expect(find.text('Balises à localiser'), findsOneWidget);
    await tester.tap(find.text('Parcours prêts'));
    await tester.pumpAndSettle();
    expect(find.text('Bois de la Bastide'), findsOneWidget);

    await tester.tap(find.text('Bois de la Bastide'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucune course sur ce parcours'), findsOneWidget);

    await tester.tap(find.text('Nouvelle course'));
    await tester.pumpAndSettle();
    // Imposed order has no allowance: the field only shows for a mode played against the clock.
    expect(find.text('Temps imparti (minutes)'), findsNothing);
    await tester.tap(find.text('Course au score'));
    await tester.pump();
    expect(find.text('Temps imparti (minutes)'), findsOneWidget);
    await tester.tap(find.text('Ordre imposé'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '2NDE B — mercredi');
    await tester.tap(find.text('Créer la course'));
    await tester.pumpAndSettle();

    expect(api.lastCreated?['name'], '2NDE B — mercredi');
    expect(api.lastCreated?.containsKey('timeLimitMinutes'), isFalse);
    expect(find.text('K7PX2M'), findsOneWidget);
    expect(find.text('Préparée'), findsOneWidget);

    await tester.tap(find.text('Démarrer'));
    await tester.pumpAndSettle();
    expect(find.text('En cours'), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);

    // Back to the menu: the started course is under « En cours », and stopped from there.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('En cours'));
    await tester.pumpAndSettle();
    expect(find.text('2NDE B — mercredi'), findsOneWidget);

    await tester.tap(find.text('Arrêter'));
    await tester.pumpAndSettle();
    expect(find.text('Arrêter la course ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Arrêter').last);
    await tester.pumpAndSettle();

    expect(api.courses.single['status'], 'closed');
    expect(find.textContaining('Aucune course en cours'), findsOneWidget);
  });
}
