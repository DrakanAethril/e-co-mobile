import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'jwt_expiry.dart';
import 'session_store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String error;

  /// The whole error body - e.g. the per-field messages of a refused course.
  final Map<String, dynamic> data;
  ApiException(this.statusCode, this.error, [this.data = const {}]);

  /// The server answered and said no for good: sending the same call again would get the same
  /// answer (an unknown checkpoint code, a runner token it does not know). A server error, a
  /// timeout or a rate limit is not a refusal - the call is worth making again later.
  bool get isRefusal => statusCode >= 400 && statusCode < 500 && statusCode != 408 && statusCode != 429;

  @override
  String toString() => 'ApiException($statusCode, $error)';
}

/// What reopening a remembered teacher session came to, at launch.
enum TeacherRestore {
  /// Nothing was remembered.
  none,

  /// Signed in again, or kept for when the network comes back.
  restored,

  /// The session is over (30 days idle, signed out from « Mon profil », account deactivated).
  expired,
}

// Thin wrapper around moncampus's e-CO endpoints (see src/Controller/Api/EcoRunnerApiController.php
// and EcoTeacherApiController.php in the moncampus repo). Runner calls are unauthenticated (a join
// token is just a request-body field, not a header).
//
// Teacher calls carry the JWT of POST /api/login, and **this class holds it**, with the refresh
// token that comes with it (App\Security\MobileSessions): the JWT lasts an hour, a race can last
// longer, so a JWT about to run out - or refused - is traded for the next one here, and the screens
// never see a token at all. The refresh token rotates at every exchange, so exchanges never run two
// at once. With « Rester connecté » the refresh token is kept in secure storage (SessionStore).
class ApiClient {
  final SessionStore? _sessionStore;

  ApiClient({SessionStore? sessionStore}) : _sessionStore = sessionStore;

  /// Called when the teacher session ends under the teacher's feet - its refresh token refused
  /// (30 days idle, signed out from « Mon profil », deactivated account). Set once in main(): it
  /// sends the teacher back to the login screen rather than leaving every screen to swallow the
  /// error - the live safety view would otherwise freeze on its last reading without saying so.
  void Function()? onTeacherSessionLost;

  String? _accessToken;
  String? _refreshToken;
  bool _staySignedIn = false;
  Future<bool>? _refreshing;
  // Several calls can be refused at once (a tab and its poll): the teacher is sent back once.
  bool _sessionLostReported = false;

  bool get hasTeacherSession => _accessToken != null || _refreshToken != null;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {String? jwt}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path, {String? jwt}) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers: {if (jwt != null) 'Authorization': 'Bearer $jwt'},
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body.isEmpty ? '{}' : response.body) as Map<String, dynamic>;
    } on FormatException {
      // An error page rather than JSON (a proxy, a deploy under way): still an answer with a
      // status, which is what decides whether the call is worth making again (isRefusal).
      if (response.statusCode >= 400) throw ApiException(response.statusCode, 'unknown');
      rethrow;
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, data['error'] as String? ?? data['message'] as String? ?? 'unknown', data);
    }
    return data;
  }

  // --- Runner (public, no account) ---

  Future<Map<String, dynamic>> runnerJoin(String pseudo, String code) =>
      _post('/api/eco/runner/join', {'pseudo': pseudo, 'code': code});

  /// What a course code resolves to, so screen 3d can confirm it as it is typed.
  Future<Map<String, dynamic>> runnerCourseByCode(String code) =>
      _get('/api/eco/runner/course?code=${Uri.encodeQueryComponent(code)}');

  Future<Map<String, dynamic>> runnerState(String token) =>
      _get('/api/eco/runner/state?token=$token');

  /// The recap of a runner who has scanned the finish (409 `runnerNotFinished` before that).
  Future<Map<String, dynamic>> runnerSummary(String token) =>
      _get('/api/eco/runner/summary?token=$token');

  /// [scannedAt] is when the runner scanned, in UTC: a scan queued without network is sent long
  /// after, and the server would otherwise date the start or the finish on its arrival.
  Future<Map<String, dynamic>> runnerScan(String token, String code, double? latitude, double? longitude,
          {String method = 'qr_scan', String? scannedAt}) =>
      _post('/api/eco/runner/scan', {
        'token': token,
        'code': code,
        'method': method,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (scannedAt != null) 'scannedAt': scannedAt,
      });

  Future<void> runnerPositions(String token, List<Map<String, dynamic>> points) async {
    await _post('/api/eco/runner/positions', {'token': token, 'points': points});
  }

  Future<void> runnerSos(String token) async {
    await _post('/api/eco/runner/sos', {'token': token});
  }

  /// [at] is when the runner left or came back, in UTC: an event queued without network is sent
  /// long after, and the server would otherwise date it on its arrival.
  Future<void> runnerAppEvent(String token, String type, {String? at}) async {
    await _post('/api/eco/runner/app-events', {'token': token, 'type': type, if (at != null) 'at': at});
  }

  // --- Teacher session ---

  Future<void> teacherLogin(String username, String password, {required bool staySignedIn}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'client': 'eco'}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || data['token'] == null) {
      throw ApiException(response.statusCode, 'loginFailed');
    }

    _accessToken = data['token'] as String;
    _refreshToken = data['refreshToken'] as String?;
    _staySignedIn = staySignedIn;
    _sessionLostReported = false;
    // « Rester connecté » off: the session lives as long as this run of the app, and a launch
    // after it must ask again - so nothing a previous session left may stay behind either.
    await _sessionStore?.clearTeacherSession();
    await _rememberRefreshToken();
  }

  /// Reopens the session « Rester connecté » kept. Without network the session is kept all the
  /// same: the first call made once the network is back asks for a JWT.
  Future<TeacherRestore> restoreTeacherSession() async {
    final store = _sessionStore;
    if (store == null) return TeacherRestore.none;

    final refreshToken = await store.loadTeacherRefreshToken();
    if (refreshToken == null) {
      // e-CO 1.2.0 kept the JWT itself: used while it lasts, then the login screen comes back once.
      final legacy = await store.takeLegacyTeacherJwt();
      if (legacy == null) return TeacherRestore.none;
      if (!isJwtUsable(legacy)) return TeacherRestore.expired;
      _accessToken = legacy;
      return TeacherRestore.restored;
    }

    _refreshToken = refreshToken;
    _staySignedIn = true;
    _sessionLostReported = false;
    try {
      await _refreshAccessToken();
    } on _SessionRefused {
      return TeacherRestore.expired;
    } catch (_) {
      // No network: kept, and asked again by the first call.
    }
    return TeacherRestore.restored;
  }

  /// « Se déconnecter »: forgotten here, and closed on the server too - a refresh token the app
  /// forgot but the server still honoured would stay usable for 30 days.
  Future<void> teacherLogout() async {
    final refreshToken = _refreshToken;
    _forgetTeacherSession();
    await _sessionStore?.clearTeacherSession();
    if (refreshToken == null) return;
    try {
      await http
          .post(
            Uri.parse('$apiBaseUrl/api/token/revoke'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline: the session will end by itself after 30 idle days, or from « Mon profil ».
    }
  }

  Future<Map<String, dynamic>> _teacherGet(String path) => _teacherCall((jwt) => _get(path, jwt: jwt));

  Future<Map<String, dynamic>> _teacherPost(String path, Map<String, dynamic> body) =>
      _teacherCall((jwt) => _post(path, body, jwt: jwt));

  /// A teacher call: a JWT renewed beforehand when it is about to run out, and renewed once more
  /// if the server refuses it anyway (its clock and ours need not agree to the second).
  Future<Map<String, dynamic>> _teacherCall(Future<Map<String, dynamic>> Function(String? jwt) send) async {
    if (_refreshToken != null && (_accessToken == null || !isJwtUsable(_accessToken!))) {
      await _refreshAccessTokenOrLoseSession();
    }

    try {
      return await send(_accessToken);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      if (_refreshToken != null) {
        await _refreshAccessTokenOrLoseSession();
        try {
          return await send(_accessToken);
        } on ApiException catch (retried) {
          if (retried.statusCode == 401) _loseSession();
          rethrow;
        }
      }
      _loseSession();
      rethrow;
    }
  }

  Future<void> _refreshAccessTokenOrLoseSession() async {
    try {
      await _refreshAccessToken();
    } on _SessionRefused {
      _loseSession();
      throw ApiException(401, 'sessionExpired');
    }
  }

  /// One exchange at a time: a second one running alongside would present the refresh token the
  /// first just replaced, which the server reads as a replay and answers by closing the session.
  Future<bool> _refreshAccessToken() => _refreshing ??= _exchangeRefreshToken().whenComplete(() => _refreshing = null);

  /// Throws [_SessionRefused] when the server refuses the refresh token; a network failure is left
  /// to the caller (http's own exception), the session untouched.
  Future<bool> _exchangeRefreshToken() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/token/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode == 401) {
      _forgetTeacherSession();
      await _sessionStore?.clearTeacherSession();
      throw _SessionRefused();
    }
    final data = _decode(response);
    _accessToken = data['token'] as String;
    _refreshToken = data['refreshToken'] as String;
    await _rememberRefreshToken();
    return true;
  }

  Future<void> _rememberRefreshToken() async {
    if (_staySignedIn && _refreshToken != null) {
      await _sessionStore?.saveTeacherRefreshToken(_refreshToken!);
    }
  }

  void _loseSession() {
    _forgetTeacherSession();
    unawaited(_sessionStore?.clearTeacherSession());
    if (_sessionLostReported) return;
    _sessionLostReported = true;
    onTeacherSessionLost?.call();
  }

  void _forgetTeacherSession() {
    _accessToken = null;
    _refreshToken = null;
  }

  // --- Teacher calls ---

  Future<Map<String, dynamic>> teacherParcoursList() => _teacherGet('/api/eco/teacher/parcours');

  Future<Map<String, dynamic>> teacherCoursesInProgress() => _teacherGet('/api/eco/teacher/courses/in-progress');

  Future<Map<String, dynamic>> teacherParcoursShow(int id) => _teacherGet('/api/eco/teacher/parcours/$id');

  /// Saves the radius of the parcours' flags: {"<checkpoint id>": metres}. Answers the parcours.
  Future<Map<String, dynamic>> teacherSaveTolerances(int parcoursId, Map<String, int> tolerances) =>
      _teacherPost('/api/eco/teacher/parcours/$parcoursId/tolerances', {'tolerances': tolerances});

  /// The IGN's reading of the parcours (App\Service\Eco\EcoTerrainSheet in moncampus).
  Future<Map<String, dynamic>> teacherParcoursTerrain(int parcoursId) =>
      _teacherGet('/api/eco/teacher/parcours/$parcoursId/terrain');

  /// Asks for a new reading; app:eco:read-terrain writes it within the minute.
  Future<Map<String, dynamic>> teacherRequestTerrain(int parcoursId) =>
      _teacherPost('/api/eco/teacher/parcours/$parcoursId/terrain', const {});

  Future<Map<String, dynamic>> teacherLocateCheckpoint(int checkpointId, double latitude, double longitude) =>
      _teacherPost('/api/eco/teacher/checkpoints/$checkpointId/locate', {'latitude': latitude, 'longitude': longitude});

  Future<Map<String, dynamic>> teacherCourseLive(int courseId) => _teacherGet('/api/eco/teacher/courses/$courseId/live');

  /// The parcours whose every flag is located - the ones a course can be run on.
  Future<Map<String, dynamic>> teacherReadyParcoursList() => _teacherGet('/api/eco/teacher/parcours/ready');

  /// A ready parcours' courses, plus the choices the creation form offers (worded server-side).
  Future<Map<String, dynamic>> teacherParcoursCourses(int parcoursId) => _teacherGet('/api/eco/teacher/parcours/$parcoursId/courses');

  Future<Map<String, dynamic>> teacherCreateCourse(int parcoursId, Map<String, dynamic> course) =>
      _teacherPost('/api/eco/teacher/parcours/$parcoursId/courses', course);

  Future<Map<String, dynamic>> teacherStartCourse(int courseId) => _teacherPost('/api/eco/teacher/courses/$courseId/start', const {});

  Future<Map<String, dynamic>> teacherCloseCourse(int courseId) => _teacherPost('/api/eco/teacher/courses/$courseId/close', const {});
}

class _SessionRefused implements Exception {}
