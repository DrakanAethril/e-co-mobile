import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/runner_session.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'race_screen.dart';
import 'teacher_login_screen.dart';

// Screen 3d - "Rejoindre une course". No account: pseudo + course code is enough.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _pseudoController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _join() async {
    final pseudo = _pseudoController.text.trim();
    final code = _codeController.text.trim();
    if (pseudo.isEmpty || code.isEmpty) {
      setState(() => _error = 'Pseudo et code requis.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final json = await api.runnerJoin(pseudo, code);
      final session = RunnerSession.fromJson(json);
      await context.read<SessionStore>().saveRunnerToken(session.token, session.pseudo);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RaceScreen(session: session)),
      );
    } on ApiException catch (e) {
      setState(() => _error = _messageFor(e.error));
    } catch (_) {
      setState(() => _error = 'Connexion impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(String error) {
    switch (error) {
      case 'courseNotFound':
        return 'Aucune course avec ce code.';
      case 'courseNotInProgress':
        return "Cette course n'est pas en cours.";
      default:
        return 'Une erreur est survenue.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              const Spacer(),
              Row(
                children: [
                  Image.asset('assets/icons/eco/ic_launcher_96.png', width: 52, height: 52),
                  const SizedBox(width: 12),
                  const Text('e-CO', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Course d'orientation à balises QR.\nPas de compte : un pseudo et le code de la course suffisent.",
                  style: TextStyle(color: Color(0xFF9FB5C8), fontSize: 14, height: 1.5),
                ),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.only(bottom: 0),
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 28),
                decoration: const BoxDecoration(
                  color: EcoColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Votre pseudo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 7),
                      TextField(controller: _pseudoController, textInputAction: TextInputAction.next),
                      const SizedBox(height: 16),
                      const Text('Code de la course', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 6, color: EcoColors.blueDark),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(color: EcoColors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loading ? null : _join,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Rejoindre la course'),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TeacherLoginScreen()),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              text: 'Enseignant ? ',
                              style: TextStyle(color: EcoColors.faint, fontSize: 12.5),
                              children: [
                                TextSpan(text: 'Se connecter', style: TextStyle(color: EcoColors.blueDark, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
