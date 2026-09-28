import 'dart:convert';

import 'package:eco/screens/splash_screen.dart';
import 'package:eco/services/api_client.dart';
import 'package:eco/services/jwt_expiry.dart';
import 'package:eco/services/session_store.dart';
import 'package:eco/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The teacher session past the JWT's hour: « Rester connecté » keeps the refresh token, ApiClient
/// trades it for the next JWT on its own - never twice at once - and a session the server has
/// ended sends the teacher back to the login screen, once.

String _jwt(Duration validFor) {
  String part(Map<String, dynamic> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;

  return '${part({'alg': 'RS256'})}.${part({'exp': exp})}.signature';
}

/// moncampus in memory: a login, a refresh that rotates, and the teacher list, which accepts only
/// the JWTs it issued and still considers valid.
class _Server {
  final paths = <String>[];
  final refreshBodies = <String>[];
  int refreshStatus = 200;
  bool offline = false;
  Duration tokenLifetime = const Duration(hours: 1);
  final _validTokens = <String>{};
  int _generation = 1;

  String _issue() {
    final token = '${_jwt(tokenLifetime)}${_validTokens.length}';
    _validTokens.add(token);
    return token;
  }

  /// A JWT the server no longer accepts, whatever its own `exp` says.
  void revokeAccessTokens() => _validTokens.clear();

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    paths.add(request.url.path);

    switch (request.url.path) {
      case '/api/login':
        return http.Response(jsonEncode({'token': _issue(), 'refreshToken': 'mcrt_1'}), 200);
      case '/api/token/refresh':
        refreshBodies.add(request.body);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (refreshStatus != 200) return http.Response('{"error":"invalid_refresh_token"}', refreshStatus);
        _generation++;
        return http.Response(jsonEncode({'token': _issue(), 'refreshToken': 'mcrt_$_generation'}), 200);
      case '/api/token/revoke':
        return http.Response('', 204);
      case '/api/eco/teacher/parcours':
        final bearer = (request.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');
        if (!_validTokens.contains(bearer)) return http.Response('{"message":"Expired JWT Token"}', 401);
        return http.Response('{"parcours":[]}', 200);
    }

    return http.Response('', 404);
  });

  int get refreshCount => paths.where((p) => p == '/api/token/refresh').length;
}

void main() {
  setUpAll(disableEcoFontFetching);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<String?> storedRefreshToken() => SessionStore().loadTeacherRefreshToken();

  group('jwt expiry', () {
    final now = DateTime(2026, 9, 28, 10);

    test('a token with time left is usable', () {
      expect(isJwtUsable(_jwt(const Duration(minutes: 30)), now: DateTime.now()), isTrue);
    });

    test('a token about to run out is not', () {
      expect(isJwtUsable(_jwt(const Duration(seconds: 20)), now: DateTime.now()), isFalse);
    });

    test('an unreadable token is not usable', () {
      expect(isJwtUsable('not-a-jwt', now: now), isFalse);
    });
  });

  group('ApiClient', () {
    test('« Rester connecté » keeps the refresh token and names the app', () async {
      final server = _Server();
      final api = ApiClient(sessionStore: SessionStore());

      await http.runWithClient(() => api.teacherLogin('prof', 'secret', staySignedIn: true), () => server.client);

      expect(await storedRefreshToken(), 'mcrt_1');
    });

    test('without « Rester connecté » nothing is written', () async {
      final server = _Server();
      final api = ApiClient(sessionStore: SessionStore());

      await http.runWithClient(() => api.teacherLogin('prof', 'secret', staySignedIn: false), () => server.client);

      expect(api.hasTeacherSession, isTrue);
      expect(await storedRefreshToken(), isNull);
    });

    test('a JWT about to run out is renewed before the call, once for calls made together', () async {
      final server = _Server()..tokenLifetime = const Duration(seconds: 30);
      final api = ApiClient(sessionStore: SessionStore());

      await http.runWithClient(() async {
        await api.teacherLogin('prof', 'secret', staySignedIn: true);
        server.tokenLifetime = const Duration(hours: 1);
        await Future.wait([api.teacherParcoursList(), api.teacherParcoursList(), api.teacherParcoursList()]);
      }, () => server.client);

      expect(server.refreshCount, 1);
      expect(await storedRefreshToken(), 'mcrt_2');
    });

    test('a JWT refused by the server is renewed and the call replayed', () async {
      final server = _Server();
      final api = ApiClient(sessionStore: SessionStore());

      final json = await http.runWithClient(() async {
        await api.teacherLogin('prof', 'secret', staySignedIn: true);
        server.revokeAccessTokens();
        return api.teacherParcoursList();
      }, () => server.client);

      expect(json['parcours'], isEmpty);
      expect(server.refreshCount, 1);
    });

    test('a session the server ended is reported once, and forgotten', () async {
      final server = _Server();
      final api = ApiClient(sessionStore: SessionStore());
      var lost = 0;
      api.onTeacherSessionLost = () => lost++;

      await http.runWithClient(() async {
        await api.teacherLogin('prof', 'secret', staySignedIn: true);
        server
          ..revokeAccessTokens()
          ..refreshStatus = 401;
        await expectLater(api.teacherParcoursList(), throwsA(isA<ApiException>()));
        await expectLater(api.teacherParcoursList(), throwsA(isA<ApiException>()));
      }, () => server.client);

      expect(lost, 1);
      expect(api.hasTeacherSession, isFalse);
      expect(await storedRefreshToken(), isNull);
    });

    test('without network at launch the remembered session is kept', () async {
      FlutterSecureStorage.setMockInitialValues({'teacher_refresh_token': 'mcrt_1'});
      final server = _Server()..offline = true;
      final api = ApiClient(sessionStore: SessionStore());

      final restore = await http.runWithClient(api.restoreTeacherSession, () => server.client);

      expect(restore, TeacherRestore.restored);
      expect(await storedRefreshToken(), 'mcrt_1');
    });

    test('signing out closes the session on the server and forgets it here', () async {
      final server = _Server();
      final api = ApiClient(sessionStore: SessionStore());

      await http.runWithClient(() async {
        await api.teacherLogin('prof', 'secret', staySignedIn: true);
        await api.teacherLogout();
      }, () => server.client);

      expect(server.paths.last, '/api/token/revoke');
      expect(api.hasTeacherSession, isFalse);
      expect(await storedRefreshToken(), isNull);
    });

    test('a JWT kept by e-CO 1.2.0 is used while it lasts, then never again', () async {
      SharedPreferences.setMockInitialValues({'teacher_jwt': _jwt(const Duration(minutes: 30))});
      final api = ApiClient(sessionStore: SessionStore());

      expect(await api.restoreTeacherSession(), TeacherRestore.restored);
      expect(await ApiClient(sessionStore: SessionStore()).restoreTeacherSession(), TeacherRestore.none);
    });
  });

  group('launch', () {
    Future<void> launch(WidgetTester tester, _Server server) async {
      await http.runWithClient(() async {
        final sessionStore = SessionStore();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<ApiClient>.value(value: ApiClient(sessionStore: sessionStore)),
              Provider<SessionStore>.value(value: sessionStore),
            ],
            child: MaterialApp(theme: ecoTheme(), home: const SplashScreen()),
          ),
        );
        await tester.pumpAndSettle();
        // The refresh answers after a short delay; real time has to pass for it.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }, () => server.client);
    }

    testWidgets('a remembered session reopens the teacher menu', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'teacher_refresh_token': 'mcrt_1'});

      await launch(tester, _Server());

      expect(find.text('Balises à localiser'), findsOneWidget);
      expect(find.text('Parcours prêts'), findsOneWidget);
    });

    testWidgets('an ended session lands on the login screen, saying why', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'teacher_refresh_token': 'mcrt_1'});

      await launch(tester, _Server()..refreshStatus = 401);

      expect(find.text('Votre session a expiré : reconnectez-vous.'), findsOneWidget);
    });

    testWidgets('without a remembered session the app opens on the join screen', (tester) async {
      await launch(tester, _Server());

      expect(find.text('Rejoindre la course'), findsOneWidget);
    });

    testWidgets('signing out asks first, then closes the session', (tester) async {
      FlutterSecureStorage.setMockInitialValues({'teacher_refresh_token': 'mcrt_1'});
      final server = _Server();
      await launch(tester, server);

      await http.runWithClient(() async {
        await tester.tap(find.byTooltip('Se déconnecter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(await tester.runAsync(storedRefreshToken), isNotNull);

        await tester.tap(find.byTooltip('Se déconnecter'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Se déconnecter'));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }, () => server.client);

      expect(server.paths.last, '/api/token/revoke');
      expect(find.text('Rejoindre la course'), findsOneWidget);
    });
  });
}
