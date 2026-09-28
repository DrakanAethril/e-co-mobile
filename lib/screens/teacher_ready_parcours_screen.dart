import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/teacher_logout_button.dart';
import 'teacher_courses_screen.dart';

// « Parcours prêts », the second tab of TeacherHomeScreen - the parcours whose every flag is
// located, the only ones a course can be run on (the web screen 1g holds the same rule).
class TeacherReadyParcoursScreen extends StatefulWidget {
  const TeacherReadyParcoursScreen({super.key});

  @override
  State<TeacherReadyParcoursScreen> createState() => _TeacherReadyParcoursScreenState();
}

class _TeacherReadyParcoursScreenState extends State<TeacherReadyParcoursScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<ApiClient>();
    final json = await api.teacherReadyParcoursList();
    return (json['parcours'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcours prêts'), actions: const [TeacherLogoutButton()]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('Chargement impossible — vérifiez la connexion.', retry: true);
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final parcoursList = snapshot.data!;
          if (parcoursList.isEmpty) {
            return _message("Aucun parcours prêt : toutes les balises d'un parcours doivent être localisées avant d'y lancer une course.");
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: parcoursList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _parcoursTile(parcoursList[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _parcoursTile(Map<String, dynamic> parcours) {
    final inProgress = (parcours['inProgressCount'] as num?)?.toInt() ?? 0;
    final prepared = (parcours['preparedCount'] as num?)?.toInt() ?? 0;
    final checkpoints = (parcours['checkpointCount'] as num?)?.toInt() ?? 0;
    final details = <String>[
      '$checkpoints balises localisées',
      if (inProgress > 0) '$inProgress en cours',
      if (prepared > 0) prepared > 1 ? '$prepared préparées' : '1 préparée',
    ];

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: EcoColors.border)),
      child: ListTile(
        title: Text(parcours['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(details.join(' · '), style: TextStyle(color: inProgress > 0 ? EcoColors.greenTx : null)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (_) => TeacherCoursesScreen(parcoursId: parcours['id'] as int, parcoursName: parcours['name'] as String),
            ))
            .then((_) => _refresh()),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: EcoFont.sans(size: 14, color: EcoColors.muted, height: 1.4)),
            if (retry) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: _refresh, child: const Text('Réessayer')),
            ],
          ],
        ),
      ),
    );
  }
}
