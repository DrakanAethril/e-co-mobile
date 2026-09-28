import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';
import 'join_screen.dart';
import 'teacher_home_screen.dart';

// Handoff screen 4a - the same shell as 3d, identifiant/mot de passe (moncampus LDAP account)
// instead of pseudo/code. Reuses the exact same JWT login moncampus-mobile already has
// (POST /api/login).
class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  State<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends State<TeacherLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _staySignedIn = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
      final sessionStore = context.read<SessionStore>();
      final jwt = await api.teacherLogin(username, password);
      // "Rester connecté" off means the JWT lives only as long as this run of the app: the
      // splash screen reads the store, so not writing it is what makes the next launch ask again.
      if (_staySignedIn) {
        await sessionStore.saveTeacherJwt(jwt);
      } else {
        await sessionStore.clearTeacherJwt();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TeacherHomeScreen(jwt: jwt)),
      );
    } catch (_) {
      setState(() => _error = 'Identifiant ou mot de passe incorrect.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EcoAuthShell(
      pitch: 'Espace enseignant.\nConnectez-vous avec votre compte Campus Beaupeyrat.',
      fields: [
        const EcoFieldLabel('Identifiant'),
        TextField(controller: _usernameController, textInputAction: TextInputAction.next),
        const SizedBox(height: 16),
        const EcoFieldLabel('Mot de passe'),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: EcoColors.faint),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _staySignedInRow(),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: EcoFont.sans(size: 13, color: EcoColors.red)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Se connecter', style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
        ),
      ],
      footer: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const JoinScreen()),
          ),
          child: Text.rich(
            TextSpan(
              text: 'Coureur ? ',
              style: EcoFont.sans(size: 12.5, color: EcoColors.faint),
              children: [
                TextSpan(
                  text: 'Rejoindre une course avec un code',
                  style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: EcoColors.blueDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _staySignedInRow() {
    return InkWell(
      onTap: () => setState(() => _staySignedIn = !_staySignedIn),
      child: Row(
        children: [
          Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: _staySignedIn ? EcoColors.blue : Colors.white,
              border: Border.all(color: _staySignedIn ? EcoColors.blue : EcoColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: _staySignedIn ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
          ),
          const SizedBox(width: 9),
          Text('Rester connecté', style: EcoFont.sans(size: 13, color: const Color(0xFF3D4F5C))),
        ],
      ),
    );
  }
}
