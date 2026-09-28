import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String error;

  /// The whole error body - e.g. the per-field messages of a refused course.
  final Map<String, dynamic> data;
  ApiException(this.statusCode, this.error, [this.data = const {}]);

  @override
  String toString() => 'ApiException($statusCode, $error)';
}

// Thin wrapper around moncampus's e-CO endpoints (see src/Controller/Api/EcoRunnerApiController.php
// and EcoTeacherApiController.php in the moncampus repo). Runner calls are unauthenticated (a join
// token is just a request-body field, not a header); teacher calls carry a JWT bearer token from
// POST /api/login, same as the rest of moncampus-mobile.
class ApiClient {
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
    final data = jsonDecode(response.body.isEmpty ? '{}' : response.body) as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> runnerScan(String token, String code, double? latitude, double? longitude, {String method = 'qr_scan'}) =>
      _post('/api/eco/runner/scan', {
        'token': token,
        'code': code,
        'method': method,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      });

  Future<void> runnerPositions(String token, List<Map<String, dynamic>> points) async {
    await _post('/api/eco/runner/positions', {'token': token, 'points': points});
  }

  Future<void> runnerSos(String token) async {
    await _post('/api/eco/runner/sos', {'token': token});
  }

  Future<void> runnerAppEvent(String token, String type) async {
    await _post('/api/eco/runner/app-events', {'token': token, 'type': type});
  }

  // --- Teacher (JWT) ---

  Future<String> teacherLogin(String username, String password) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || data['token'] == null) {
      throw ApiException(response.statusCode, 'loginFailed');
    }
    return data['token'] as String;
  }

  Future<Map<String, dynamic>> teacherParcoursList(String jwt) => _get('/api/eco/teacher/parcours', jwt: jwt);

  Future<Map<String, dynamic>> teacherCoursesInProgress(String jwt) => _get('/api/eco/teacher/courses/in-progress', jwt: jwt);

  Future<Map<String, dynamic>> teacherParcoursShow(String jwt, int id) => _get('/api/eco/teacher/parcours/$id', jwt: jwt);

  Future<Map<String, dynamic>> teacherLocateCheckpoint(String jwt, int checkpointId, double latitude, double longitude) =>
      _post('/api/eco/teacher/checkpoints/$checkpointId/locate', {'latitude': latitude, 'longitude': longitude}, jwt: jwt);

  Future<Map<String, dynamic>> teacherCourseLive(String jwt, int courseId) => _get('/api/eco/teacher/courses/$courseId/live', jwt: jwt);

  /// The parcours whose every flag is located - the ones a course can be run on.
  Future<Map<String, dynamic>> teacherReadyParcoursList(String jwt) => _get('/api/eco/teacher/parcours/ready', jwt: jwt);

  /// A ready parcours' courses, plus the choices the creation form offers (worded server-side).
  Future<Map<String, dynamic>> teacherParcoursCourses(String jwt, int parcoursId) =>
      _get('/api/eco/teacher/parcours/$parcoursId/courses', jwt: jwt);

  Future<Map<String, dynamic>> teacherCreateCourse(String jwt, int parcoursId, Map<String, dynamic> course) =>
      _post('/api/eco/teacher/parcours/$parcoursId/courses', course, jwt: jwt);

  Future<Map<String, dynamic>> teacherStartCourse(String jwt, int courseId) =>
      _post('/api/eco/teacher/courses/$courseId/start', const {}, jwt: jwt);

  Future<Map<String, dynamic>> teacherCloseCourse(String jwt, int courseId) =>
      _post('/api/eco/teacher/courses/$courseId/close', const {}, jwt: jwt);
}
