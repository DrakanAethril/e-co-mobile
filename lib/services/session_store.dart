import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Persisted across app restarts/crashes - "reprise après crash" (design's own term) rebuilds
// everything else from the server (GET /api/eco/runner/state) using only this token, so this
// class deliberately stores nothing but the token itself plus small display hints.
//
// The teacher's « Rester connecté » keeps one thing: the refresh token (App\Security\MobileSessions
// on the moncampus side), in the platform's secure storage since it opens the account for 30 days.
// The hour-long JWT is never written - ApiClient asks for a new one from the refresh token.
class SessionStore {
  static const _tokenKey = 'runner_token';
  static const _pseudoKey = 'runner_pseudo';
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

  Future<void> clearRunnerSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_pseudoKey);
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
