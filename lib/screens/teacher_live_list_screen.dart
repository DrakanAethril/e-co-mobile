import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import 'teacher_live_screen.dart';

class TeacherLiveListScreen extends StatefulWidget {
  final String jwt;
  const TeacherLiveListScreen({super.key, required this.jwt});

  @override
  State<TeacherLiveListScreen> createState() => _TeacherLiveListScreenState();
}

class _TeacherLiveListScreenState extends State<TeacherLiveListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<ApiClient>();
    final json = await api.teacherCoursesInProgress(widget.jwt);
    return (json['courses'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi sécurité')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final courses = snapshot.data!;
          if (courses.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucune course en cours pour le moment.', textAlign: TextAlign.center)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final course = courses[index];
              return Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: EcoColors.border)),
                child: ListTile(
                  title: Text(course['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${course['parcoursName']} · ${course['code']} · ${course['runnerCount']} coureurs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TeacherLiveScreen(jwt: widget.jwt, courseId: course['id'] as int, courseName: course['name'] as String)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
