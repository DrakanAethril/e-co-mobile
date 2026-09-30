import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/runner_session.dart';
import '../services/api_client.dart';
import '../services/session_store.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';
import 'race_screen.dart';
import 'teacher_login_screen.dart';

// Handoff screen 3d - "Rejoindre une course". No account: pseudo + course code is enough, and the
// code is confirmed back as it is typed so a mistyped character is caught before the button.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  static const int _codeLength = 6;

  final _pseudoController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  Timer? _lookupDebounce;
  Map<String, dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _pseudoController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Looks the code up once it is complete, off a short debounce so a fast typist doesn't fire six
  /// requests on the way there.
  void _onCodeChanged() {
    final code = _codeController.text.trim().toUpperCase();
    _lookupDebounce?.cancel();

    if (code.length != _codeLength) {
      if (_preview != null) setState(() => _preview = null);

      return;
    }

    _lookupDebounce = Timer(const Duration(milliseconds: 350), () => _lookupCode(code));
  }

  Future<void> _lookupCode(String code) async {
    try {
      final json = await context.read<ApiClient>().runnerCourseByCode(code);
      if (mounted) setState(() => _preview = json);
    } catch (_) {
      // Unknown code, or no network: the join call is what will say so out loud.
      if (mounted) setState(() => _preview = null);
    }
  }

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
      final sessionStore = context.read<SessionStore>();
      final json = await api.runnerJoin(pseudo, code);
      final session = RunnerSession.fromJson(json);
      await sessionStore.saveRunnerToken(session.token, session.pseudo);

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
    return EcoAuthShell(
      pitch: "Course d'orientation à balises QR.\n"
          'Pas de compte : un pseudo et le code de la course suffisent.',
      fields: [
        const EcoFieldLabel('Votre pseudo'),
        TextField(controller: _pseudoController, textInputAction: TextInputAction.next),
        const SizedBox(height: 16),
        const EcoFieldLabel('Code de la course'),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: _codeLength,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          style: EcoFont.mono(size: 22, weight: FontWeight.w700, color: EcoColors.blueDark, letterSpacing: 8),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 7),
          _coursePreview(_preview!),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: EcoFont.sans(size: 13, color: EcoColors.red)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _join,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Rejoindre la course', style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
        ),
      ],
      footer: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TeacherLoginScreen()),
          ),
          child: Text.rich(
            TextSpan(
              text: 'Enseignant ? ',
              style: EcoFont.sans(size: 12.5, color: EcoColors.faint),
              children: [
                TextSpan(
                  text: 'Se connecter',
                  style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: EcoColors.blueDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "✓ Course « 2NDE B — mercredi » · en cours · ordre imposé" - green when the course can be
  /// joined, gold when it exists but is not running yet.
  Widget _coursePreview(Map<String, dynamic> preview) {
    final joinable = preview['joinable'] == true;
    final color = joinable ? EcoColors.greenTx : EcoColors.goldTx;
    final mode = preview['modeLabel'] as String? ?? switch (preview['mode'] as String?) {
      'free_order' => 'ordre libre',
      'score' => 'course au score',
      _ => 'ordre imposé',
    };
    final status = switch (preview['status'] as String?) {
      'in_progress' => 'en cours',
      'closed' => 'clôturée',
      _ => 'pas encore démarrée',
    };

    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: joinable ? EcoColors.green : EcoColors.gold, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Icon(joinable ? Icons.check : Icons.schedule, size: 10, color: Colors.white),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Course « ${preview['name']} » · $status · $mode',
            style: EcoFont.sans(size: 12, weight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}
