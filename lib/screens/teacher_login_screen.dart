import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'join_screen.dart';
import 'teacher_parcours_list_screen.dart';

// Screen 4a - same shell as 3d, identifiant/mot de passe (moncampus LDAP account) instead of
// pseudo/code. Reuses the exact same JWT login moncampus-mobile already has (POST /api/login).
class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  State<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends State<TeacherLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Identifiant et mot de passe requis.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final jwt = await api.teacherLogin(username, password);
      await context.read<SessionStore>().saveTeacherJwt(jwt);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TeacherParcoursListScreen(jwt: jwt)),
      );
    } catch (_) {
      setState(() => _error = 'Identifiant ou mot de passe incorrect.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('e', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: EcoColors.blue)),
                  ),
                  const SizedBox(width: 12),
                  const Text('e-CO', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Espace enseignant.\nConnectez-vous avec votre compte Campus Beaupeyrat.',
                  style: TextStyle(color: Color(0xFF9FB5C8), fontSize: 14, height: 1.5),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 28),
                decoration: const BoxDecoration(color: EcoColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Identifiant', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 7),
                      TextField(controller: _usernameController, textInputAction: TextInputAction.next),
                      const SizedBox(height: 16),
                      const Text('Mot de passe', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(color: EcoColors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const JoinScreen()),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              text: 'Coureur ? ',
                              style: TextStyle(color: EcoColors.faint, fontSize: 12.5),
                              children: [
                                TextSpan(text: 'Rejoindre une course avec un code', style: TextStyle(color: EcoColors.blueDark, fontWeight: FontWeight.w600)),
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
