import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

// Web screen 1e on the phone - the parcours' flags with their code, where they stand, and the
// radius each one is validated within, which is the one thing edited here, as on the web. The
// IGN's advice (a canopy calling for a wider radius) is one tap away from the field; nothing is
// saved until « Enregistrer ».
class TeacherParcoursEditScreen extends StatefulWidget {
  final int parcoursId;
  final String parcoursName;
  const TeacherParcoursEditScreen({super.key, required this.parcoursId, required this.parcoursName});

  @override
  State<TeacherParcoursEditScreen> createState() => _TeacherParcoursEditScreenState();
}

class _TeacherParcoursEditScreenState extends State<TeacherParcoursEditScreen> {
  List<Map<String, dynamic>> _checkpoints = [];
  final Map<int, TextEditingController> _fields = {};
  int _defaultTolerance = 20;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      _show(await context.read<ApiClient>().teacherParcoursShow(widget.parcoursId));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _show(Map<String, dynamic> json) {
    if (!mounted) return;
    final checkpoints = (json['checkpoints'] as List).cast<Map<String, dynamic>>();
    for (final checkpoint in checkpoints) {
      final id = checkpoint['id'] as int;
      final value = '${(checkpoint['toleranceMeters'] as num?)?.toInt() ?? ''}';
      (_fields[id] ??= TextEditingController()).text = value;
    }
    setState(() {
      _checkpoints = checkpoints;
      _defaultTolerance = (json['defaultToleranceMeters'] as num?)?.toInt() ?? 20;
      _loading = false;
      _failed = false;
    });
  }

  Future<void> _save() async {
    final tolerances = <String, int>{};
    for (final entry in _fields.entries) {
      final meters = int.tryParse(entry.value.text.trim());
      if (meters != null) tolerances['${entry.key}'] = meters;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      _show(await context.read<ApiClient>().teacherSaveTolerances(widget.parcoursId, tolerances));
      messenger.showSnackBar(const SnackBar(content: Text('Parcours enregistré.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Échec de l'enregistrement — vérifiez la connexion.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.bg,
      body: Column(
        children: [
          EcoScreenHeader(title: widget.parcoursName, subtitle: 'Balises et tolérances'),
          Expanded(child: _body()),
          if (!_loading && !_failed) _bottomBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Chargement impossible — vérifiez la connexion.', style: EcoFont.sans(size: 14, color: EcoColors.muted)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final checkpoint in _checkpoints) ...[
          _checkpointCard(checkpoint),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Text(
          'Tolérance par défaut : $_defaultTolerance m — modifiable balise par balise. '
          'Le code court permet la validation manuelle si le QR est illisible.',
          style: EcoFont.sans(size: 12, color: EcoColors.faint, height: 1.4),
        ),
      ],
    );
  }

  Widget _checkpointCard(Map<String, dynamic> checkpoint) {
    final id = checkpoint['id'] as int;
    final located = checkpoint['located'] == true;
    final note = checkpoint['note'] as String?;
    final advised = (checkpoint['advisedToleranceMeters'] as num?)?.toInt();
    final canopy = (checkpoint['canopyHeight'] as num?)?.toDouble();
    final field = _fields[id]!;
    final overridden = int.tryParse(field.text) != _defaultTolerance;

    return EcoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: checkpoint['type'] == 'checkpoint' ? EcoColors.greenBg : EcoColors.blueBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  _shortLabel(checkpoint),
                  style: EcoFont.spectral(
                    size: 15,
                    weight: FontWeight.w700,
                    color: checkpoint['type'] == 'checkpoint' ? EcoColors.greenTx : EcoColors.blueDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(
                      text: checkpoint['name'] as String,
                      style: EcoFont.sans(size: 14, weight: FontWeight.w600),
                      children: [
                        if (note != null && note.isNotEmpty)
                          TextSpan(text: ' ($note)', style: EcoFont.sans(size: 12, color: EcoColors.faint)),
                      ],
                    )),
                    Text(
                      located ? '● Localisée' : '● À localiser',
                      style: EcoFont.sans(size: 11.5, color: located ? EcoColors.greenTx : EcoColors.goldTx),
                    ),
                  ],
                ),
              ),
              Text('${checkpoint['shortCode'] ?? ''}', style: EcoFont.mono(size: 13, color: EcoColors.blueDark, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Tolérance', style: EcoFont.sans(size: 12.5, color: EcoColors.muted)),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: TextField(
                  key: ValueKey('tolerance-$id'),
                  controller: field,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'm',
                    filled: overridden,
                    fillColor: EcoColors.goldBg,
                  ),
                ),
              ),
              const Spacer(),
              // The canopy over this flag calls for a wider radius than it has: one tap fills the
              // field, the teacher still saves.
              if (advised != null)
                TextButton(
                  onPressed: () => setState(() => field.text = '$advised'),
                  style: TextButton.styleFrom(foregroundColor: EcoColors.goldTx, padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(
                    'Conseillé : $advised m',
                    style: EcoFont.sans(size: 12, weight: FontWeight.w600, color: EcoColors.goldTx),
                  ),
                ),
            ],
          ),
          if (advised != null && canopy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Végétation de ${canopy.round()} m autour de la balise : sous le couvert, le GPS d'un téléphone dérive davantage.",
                style: EcoFont.sans(size: 11, color: EcoColors.faint, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: EcoColors.border))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer',
                style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  String _shortLabel(Map<String, dynamic> checkpoint) => switch (checkpoint['type']) {
        'start' => 'D',
        'finish' => 'A',
        _ => '${checkpoint['position']}',
      };
}
