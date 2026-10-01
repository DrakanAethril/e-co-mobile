import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/runner_session.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'join_screen.dart';
import 'race_screen.dart';
import 'teacher_home_screen.dart';
import 'teacher_login_screen.dart';

// "Reprise après crash" entry point - if a runner token is persisted locally, resume straight
// into the race from server state (GET /api/eco/runner/state) instead of ever showing the join
// screen again. An invalid/expired token (course was deleted, etc.) just falls through to the
// normal home choice. Then « Rester connecté »: a remembered teacher session reopens the teacher
// menu (ApiClient.restoreTeacherSession) - an ended one lands on the login screen, saying so.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _resume() async {
    final sessionStore = context.read<SessionStore>();
    final api = context.read<ApiClient>();
    final token = await sessionStore.loadRunnerToken();

    if (token != null) {
      RunnerSession? session;
      try {
        session = RunnerSession.fromJson(await api.runnerState(token));
      } on ApiException catch (e) {
        // The server does not know this runner any more: over for good. Any other answer (a
        // server error) is a relaunch without a usable network - the race goes on from the last
        // state kept, and the race screen asks /state again by itself.
        if (e.isRefusal) {
          await sessionStore.clearRunnerSession();
        } else {
          session = await _lastKnown(sessionStore, token);
        }
      } catch (_) {
        // No network: a relaunch in a dead zone must not end the race (nor orphan the queue).
        session = await _lastKnown(sessionStore, token);
      }
      if (session != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RaceScreen(session: session!)),
        );
        return;
      }
    }

    final restore = await api.restoreTeacherSession();
    if (restore != TeacherRestore.none) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => restore == TeacherRestore.restored
              ? const TeacherHomeScreen()
              : const TeacherLoginScreen(notice: 'Votre session a expiré : reconnectez-vous.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const JoinScreen()),
    );
  }

  /// The state kept at the last moment the race screen knew it. Without one (an app updated
  /// offline from a version that kept none) the token is left in place: the next launch with
  /// network resumes the race from /state.
  Future<RunnerSession?> _lastKnown(SessionStore sessionStore, String token) async {
    final snapshot = await sessionStore.loadRunnerSnapshot(token);
    if (snapshot == null) return null;
    try {
      return RunnerSession.fromJson(snapshot);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: EcoColors.navy,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
