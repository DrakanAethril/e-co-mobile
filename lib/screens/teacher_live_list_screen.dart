import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/teacher_logout_button.dart';
import 'teacher_course_actions.dart';
import 'teacher_live_screen.dart';

// « En cours », the third tab of TeacherHomeScreen - every course running on this teacher's
// parcours: open one to follow it live (4d), or stop it from here.
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

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _close(Map<String, dynamic> course) async {
    final closed = await confirmAndCloseCourse(context, widget.jwt, course['id'] as int, course['name'] as String);
    if (closed && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses en cours'), actions: const [TeacherLogoutButton()]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chargement impossible — vérifiez la connexion.'),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _refresh, child: const Text('Réessayer')),
                ],
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final courses = snapshot.data!;
          if (courses.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucune course en cours pour le moment.\nDémarrez-en une depuis « Parcours prêts ».', textAlign: TextAlign.center)));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _close(course),
                          style: TextButton.styleFrom(foregroundColor: EcoColors.red),
                          child: const Text('Arrêter', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TeacherLiveScreen(jwt: widget.jwt, courseId: course['id'] as int, courseName: course['name'] as String)))
                        .then((_) => _refresh()),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
