import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import 'teacher_locate_screen.dart';

// « À localiser », the first tab of TeacherHomeScreen - parcours still needing checkpoints located
// (screen 4b's list). Once every flag is located a parcours moves to « Parcours prêts ».
class TeacherParcoursListScreen extends StatefulWidget {
  final String jwt;
  const TeacherParcoursListScreen({super.key, required this.jwt});

  @override
  State<TeacherParcoursListScreen> createState() => _TeacherParcoursListScreenState();
}

class _TeacherParcoursListScreenState extends State<TeacherParcoursListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<ApiClient>();
    final json = await api.teacherParcoursList(widget.jwt);
    return (json['parcours'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balises à localiser')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final parcoursList = snapshot.data!;
          if (parcoursList.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tous vos parcours sont localisés.\nLancez une course depuis « Parcours prêts ».', textAlign: TextAlign.center)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: parcoursList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final p = parcoursList[index];
              return Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: EcoColors.border)),
                child: ListTile(
                  title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${p['locatedCount']}/${p['totalCount']} balises localisées'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TeacherLocateScreen(jwt: widget.jwt, parcoursId: p['id'] as int, parcoursName: p['name'] as String)),
                  ).then((_) => setState(() => _future = _load())),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
