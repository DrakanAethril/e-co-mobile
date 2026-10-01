import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Persisted across app restarts/crashes - "reprise après crash" (design's own term) rebuilds
// everything else from the server (GET /api/eco/runner/state) using only this token. Beside it,
// the last state of the race the screen showed: a relaunch without network starts from it rather
// than from nothing - the race goes on, the queue keeps its token - and /state replaces it as soon
// as it answers.
//
// The teacher's « Rester connecté » keeps one thing: the refresh token (App\Security\MobileSessions
// on the moncampus side), in the platform's secure storage since it opens the account for 30 days.
// The hour-long JWT is never written - ApiClient asks for a new one from the refresh token.
class SessionStore {
  static const _tokenKey = 'runner_token';
  static const _pseudoKey = 'runner_pseudo';
  static const _snapshotKey = 'runner_session_snapshot';
  // Written by e-CO 1.2.0, before the refresh token: read once so an upgrade does not sign out a
  // teacher whose JWT still has time left, then removed.
  static const _legacyTeacherJwtKey = 'teacher_jwt';
  static const _teacherRefreshTokenKey = 'teacher_refresh_token';

  final FlutterSecureStorage _secureStorage;

  SessionStore({FlutterSecureStorage? secureStorage}) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> saveRunnerToken(String token, String pseudo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_pseudoKey, pseudo);
  }

  Future<String?> loadRunnerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveRunnerSnapshot(Map<String, dynamic> session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(session));
  }

  /// The last state kept for [token] - null when none, or when it belongs to another race.
  Future<Map<String, dynamic>?> loadRunnerSnapshot(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null) return null;
    try {
      final session = jsonDecode(raw) as Map<String, dynamic>;
      return session['token'] == token ? session : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRunnerSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_pseudoKey);
    await prefs.remove(_snapshotKey);
  }

  Future<void> saveTeacherRefreshToken(String refreshToken) =>
      _secureStorage.write(key: _teacherRefreshTokenKey, value: refreshToken);

  Future<String?> loadTeacherRefreshToken() => _secureStorage.read(key: _teacherRefreshTokenKey);

  /// The JWT an older version remembered, if any - taken, never put back.
  Future<String?> takeLegacyTeacherJwt() async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString(_legacyTeacherJwtKey);
    if (jwt != null) await prefs.remove(_legacyTeacherJwtKey);
    return jwt;
  }

  Future<void> clearTeacherSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTeacherJwtKey);
    await _secureStorage.delete(key: _teacherRefreshTokenKey);
  }
}
