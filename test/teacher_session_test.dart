import 'dart:convert';

import 'package:eco/screens/splash_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/services/jwt_expiry.dart';
import 'package:eco/services/session_store.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « Rester connecté » and « Se déconnecter »: a stored teacher token reopens the teacher menu
/// until it runs out, an expired one says so on the login screen, and signing out forgets it.

String _jwt(DateTime expiresAt) {
  String part(Map<String, dynamic> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  return '${part({'alg': 'RS256'})}.${part({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, 'username': 'prof'})}.signature';
}

class _EmptyTeacherApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> teacherParcoursList(String jwt) async => {'parcours': []};
}

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _EmptyTeacherApi()),
        Provider<SessionStore>.value(value: SessionStore()),
      ],
      child: MaterialApp(theme: ecoTheme(), home: const SplashScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<String?> _storedJwt() async => (await SharedPreferences.getInstance()).getString('teacher_jwt');

void main() {
  setUpAll(disableEcoFontFetching);

  group('jwt expiry', () {
    final now = DateTime(2026, 9, 28, 10);

    test('a token with time left is usable', () {
      expect(isJwtUsable(_jwt(now.add(const Duration(minutes: 30))), now: now), isTrue);
    });

    test('a token about to run out is not resumed', () {
      expect(isJwtUsable(_jwt(now.add(const Duration(seconds: 20))), now: now), isFalse);
    });

    test('an unreadable token is not usable', () {
      expect(isJwtUsable('not-a-jwt', now: now), isFalse);
    });
  });

  testWidgets('a stored token reopens the teacher menu', (tester) async {
    SharedPreferences.setMockInitialValues({'teacher_jwt': _jwt(DateTime.now().add(const Duration(minutes: 40)))});

    await _launch(tester);

    expect(find.text('Balises à localiser'), findsOneWidget);
    expect(find.text('Parcours prêts'), findsOneWidget);
  });

  testWidgets('an expired token is forgotten and the login screen says why', (tester) async {
    SharedPreferences.setMockInitialValues({'teacher_jwt': _jwt(DateTime.now().subtract(const Duration(minutes: 5)))});

    await _launch(tester);

    expect(find.text('Votre session a expiré : reconnectez-vous.'), findsOneWidget);
    expect(await _storedJwt(), isNull);
  });

  testWidgets('without a stored token the app opens on the join screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await _launch(tester);

    expect(find.text('Rejoindre la course'), findsOneWidget);
  });

  testWidgets('signing out asks first, then forgets the token', (tester) async {
    SharedPreferences.setMockInitialValues({'teacher_jwt': _jwt(DateTime.now().add(const Duration(minutes: 40)))});
    await _launch(tester);

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(await _storedJwt(), isNotNull);

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Se déconnecter'));
    await tester.pumpAndSettle();

    expect(await _storedJwt(), isNull);
    expect(find.text('Rejoindre la course'), findsOneWidget);
  });

  test('a refused teacher token is reported once, a refused runner token never', () async {
    final api = ApiClient();
    var lost = 0;
    api.onTeacherSessionLost = () => lost++;

    await http.runWithClient(() async {
      await expectLater(api.teacherParcoursList('expired'), throwsA(isA<ApiException>()));
      await expectLater(api.teacherCoursesInProgress('expired'), throwsA(isA<ApiException>()));
      await expectLater(api.runnerState('stale-runner-token'), throwsA(isA<ApiException>()));
    }, () => MockClient((_) async => http.Response('{"error":"invalidToken"}', 401)));

    expect(lost, 1);
  });
}
