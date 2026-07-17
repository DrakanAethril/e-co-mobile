import 'package:shared_preferences/shared_preferences.dart';

// Persisted across app restarts/crashes - "reprise après crash" (design's own term) rebuilds
// everything else from the server (GET /api/eco/runner/state) using only this token, so this
// class deliberately stores nothing but the token itself plus small display hints.
class SessionStore {
  static const _tokenKey = 'runner_token';
  static const _pseudoKey = 'runner_pseudo';
  static const _teacherJwtKey = 'teacher_jwt';

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

  Future<void> saveTeacherJwt(String jwt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_teacherJwtKey, jwt);
  }

  Future<String?> loadTeacherJwt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_teacherJwtKey);
  }

  Future<void> clearTeacherJwt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_teacherJwtKey);
  }
}
