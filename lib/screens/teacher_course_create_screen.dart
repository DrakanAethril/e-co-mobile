import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

// Web screen 1g's « Nouvelle course » panel on the phone. The choices (modes, map visibility) and
// their wording come from the server, the rules too (EcoCourseType): this screen only collects.
// Pops with the created course, whose join code the server has just drawn.
class TeacherCourseCreateScreen extends StatefulWidget {
  final int parcoursId;
  final String parcoursName;
  final Map<String, dynamic> options;
  const TeacherCourseCreateScreen({
    super.key,
    required this.parcoursId,
    required this.parcoursName,
    required this.options,
  });

  @override
  State<TeacherCourseCreateScreen> createState() => _TeacherCourseCreateScreenState();
}

class _TeacherCourseCreateScreenState extends State<TeacherCourseCreateScreen> {
  final _nameController = TextEditingController();
  final _timeLimitController = TextEditingController();
  late final List<Map<String, dynamic>> _modes;
  late final List<Map<String, dynamic>> _mapVisibilities;
  // « Balises spécifiques »: the numbered flags to pick from (Départ and Arrivée are part of every
  // race), the ones picked, and whether they are run in order.
  late final List<Map<String, dynamic>> _checkpoints;
  final Set<int> _selectedCheckpointIds = {};
  bool _specificOrdered = true;
  late String _mode;
  late String _mapVisibility;
  bool _teamsEnabled = false;
  bool _safetyAlertsEnabled = true;
  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _modes = (widget.options['modes'] as List? ?? const []).cast<Map<String, dynamic>>();
    _mapVisibilities = (widget.options['mapVisibilities'] as List? ?? const []).cast<Map<String, dynamic>>();
    _checkpoints = (widget.options['checkpoints'] as List? ?? const []).cast<Map<String, dynamic>>();
    // The server lists the entity's defaults first (imposed order, every checkpoint shown).
    _mode = _modes.isNotEmpty ? _modes.first['value'] as String : 'imposed_order';
    _mapVisibility = _mapVisibilities.isNotEmpty ? _mapVisibilities.first['value'] as String : 'all_checkpoints';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeLimitController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _selectedMode {
    for (final mode in _modes) {
      if (mode['value'] == _mode) return mode;
    }

    return null;
  }

  bool get _checkpointSelection => _selectedMode?['checkpointSelection'] == true;

  // A race run in order is ranked on time: in « Balises spécifiques » that depends on the order
  // chosen, the server's own rule (EcoCourse::isTimeLimited()).
  bool get _timeLimited => _checkpointSelection ? !_specificOrdered : _selectedMode?['timeLimited'] == true;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _fieldErrors = const {'name': 'Donnez un nom à la course.'});
      return;
    }

    setState(() {
      _saving = true;
      _fieldErrors = const {};
      _error = null;
    });

    final api = context.read<ApiClient>();
    final timeLimit = int.tryParse(_timeLimitController.text.trim());
    try {
      final json = await api.teacherCreateCourse(widget.parcoursId, {
        'name': name,
        'mode': _mode,
        if (_checkpointSelection) ...{
          'specificCheckpointIds': _selectedCheckpointIds.toList(),
          'specificOrdered': _specificOrdered,
        },
        if (_timeLimited && timeLimit != null) 'timeLimitMinutes': timeLimit,
        'mapVisibility': _mapVisibility,
        'teamsEnabled': _teamsEnabled,
        'safetyAlertsEnabled': _safetyAlertsEnabled,
      });
      if (!mounted) return;
      Navigator.of(context).pop((json['course'] as Map).cast<String, dynamic>());
    } on ApiException catch (e) {
      // The server names the refused fields; the wording is the app's, in French whatever the
      // language the validator answered in.
      final fields = e.data['fields'];
      setState(() {
        _fieldErrors = fields is Map ? {for (final key in fields.keys) '$key': _fieldMessage('$key')} : const {};
        _error = _fieldErrors.isEmpty ? 'Création impossible.' : null;
      });
    } catch (_) {
      setState(() => _error = 'Création impossible — vérifiez la connexion.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EcoScreenHeader(title: 'Nouvelle course', subtitle: widget.parcoursName),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                const EcoFieldLabel('Nom'),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: 'ex. 2NDE B — mercredi', errorText: _fieldErrors['name']),
                ),
                const SizedBox(height: 20),
                const EcoFieldLabel('Mode de course'),
                for (final mode in _modes) _modeCard(mode),
                if (_fieldErrors['mode'] != null) _fieldError(_fieldErrors['mode']!),
                if (_checkpointSelection) _specificCheckpoints(),
                if (_timeLimited) ...[
                  const SizedBox(height: 12),
                  const EcoFieldLabel('Temps imparti (minutes)'),
                  TextField(
                    controller: _timeLimitController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(hintText: '45', errorText: _fieldErrors['timeLimitMinutes']),
                  ),
                ],
                const SizedBox(height: 20),
                const EcoFieldLabel('Carte du coureur'),
                DropdownButtonFormField<String>(
                  value: _mapVisibility,
                  isExpanded: true,
                  items: [
                    for (final visibility in _mapVisibilities)
                      DropdownMenuItem(value: visibility['value'] as String, child: Text(visibility['label'] as String)),
                  ],
                  onChanged: (value) => setState(() => _mapVisibility = value ?? _mapVisibility),
                  decoration: InputDecoration(errorText: _fieldErrors['mapVisibility']),
                ),
                const SizedBox(height: 6),
                Text("La position du coureur n'apparaît jamais sur sa carte.", style: EcoFont.sans(size: 12, color: EcoColors.faint)),
                const SizedBox(height: 14),
                _switch('Course par équipes (binômes / groupes)', _teamsEnabled, (value) => setState(() => _teamsEnabled = value)),
                _switch('Alertes sécurité (immobile / sans signal > 4 min)', _safetyAlertsEnabled, (value) => setState(() => _safetyAlertsEnabled = value)),
                const SizedBox(height: 8),
                Text(
                  'Le code de la course est tiré à la création. Elle reste « Préparée » tant que vous ne la démarrez pas.',
                  style: EcoFont.sans(size: 12, color: EcoColors.faint, height: 1.4),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: EcoFont.sans(size: 13, color: EcoColors.red)),
                ],
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: EcoColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Créer la course', style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The web form's radio cards: the mode's name, and what it ranks on underneath.
  Widget _modeCard(Map<String, dynamic> mode) {
    final selected = mode['value'] == _mode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _mode = mode['value'] as String),
        child: EcoCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          background: selected ? EcoColors.blueBgSoft : Colors.white,
          borderColor: selected ? EcoColors.blue : EcoColors.border,
          borderWidth: selected ? 1.5 : 1,
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: selected ? EcoColors.blue : EcoColors.faint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode['label'] as String, style: EcoFont.sans(size: 14, weight: FontWeight.w600)),
                    Text(mode['description'] as String? ?? '', style: EcoFont.sans(size: 12, color: EcoColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// « Balises spécifiques »: in order or not, then the flags - the others do not exist for the race.
  Widget _specificCheckpoints() {
    final orders = (widget.options['specificOrders'] as List? ?? const []).cast<Map<String, dynamic>>();

    return EcoCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      background: EcoColors.blueBgSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EcoFieldLabel('Ordre de passage'),
          for (final order in orders)
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: order['value'] == true,
              groupValue: _specificOrdered,
              activeColor: EcoColors.blue,
              onChanged: (value) => setState(() => _specificOrdered = value ?? _specificOrdered),
              title: Text(order['label'] as String, style: EcoFont.sans(size: 13.5)),
            ),
          const SizedBox(height: 6),
          const EcoFieldLabel('Balises à trouver'),
          for (final checkpoint in _checkpoints) _checkpointTile(checkpoint),
          if (_fieldErrors['specificCheckpoints'] != null) _fieldError(_fieldErrors['specificCheckpoints']!),
          const SizedBox(height: 4),
          Text(
            "Départ et Arrivée font partie de toute course. Les balises non cochées n'existent pas pour celle-ci.",
            style: EcoFont.sans(size: 12, color: EcoColors.faint, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _checkpointTile(Map<String, dynamic> checkpoint) {
    final id = (checkpoint['id'] as num).toInt();
    final note = checkpoint['note'] as String?;

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: EcoColors.blue,
      value: _selectedCheckpointIds.contains(id),
      onChanged: (checked) => setState(() => checked == true ? _selectedCheckpointIds.add(id) : _selectedCheckpointIds.remove(id)),
      title: Text(
        note != null && note.isNotEmpty ? '${checkpoint['name']} ($note)' : checkpoint['name'] as String,
        style: EcoFont.sans(size: 13.5),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeColor: EcoColors.blue,
      title: Text(label, style: EcoFont.sans(size: 13.5)),
    );
  }

  String _fieldMessage(String field) => switch (field) {
        'name' => 'Donnez un nom à la course.',
        'timeLimitMinutes' => 'Indiquez un nombre de minutes supérieur à 0.',
        'mode' => 'Choisissez un mode de course.',
        'specificCheckpoints' => 'Cochez au moins une balise.',
        'mapVisibility' => 'Choisissez ce que montre la carte.',
        _ => 'Valeur refusée.',
      };

  Widget _fieldError(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(message, style: EcoFont.sans(size: 12, color: EcoColors.red)),
    );
  }
}
