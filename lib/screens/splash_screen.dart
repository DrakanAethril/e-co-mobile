import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/runner_session.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'join_screen.dart';
import 'race_screen.dart';

// "Reprise après crash" entry point - if a runner token is persisted locally, resume straight
// into the race from server state (GET /api/eco/runner/state) instead of ever showing the join
// screen again. An invalid/expired token (course was deleted, etc.) just falls through to the
// normal home choice.
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
      try {
        final json = await api.runnerState(token);
        final session = RunnerSession.fromJson(json);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RaceScreen(session: session)),
        );
        return;
      } catch (_) {
        await sessionStore.clearRunnerSession();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const JoinScreen()),
    );
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
