import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';
import '../widgets/teacher_parcours_links.dart';
import 'teacher_course_actions.dart';
import 'teacher_course_create_screen.dart';
import 'teacher_live_screen.dart';

// Web screen 1g on the phone - a ready parcours' courses, newest first: create one, start it,
// follow it live, stop it. The join code is shown large on every course still to be run, since
// the teacher reads it out to the class from this screen.
class TeacherCoursesScreen extends StatefulWidget {
  final int parcoursId;
  final String parcoursName;
  const TeacherCoursesScreen({super.key, required this.parcoursId, required this.parcoursName});

  @override
  State<TeacherCoursesScreen> createState() => _TeacherCoursesScreenState();
}

class _TeacherCoursesScreenState extends State<TeacherCoursesScreen> {
  List<Map<String, dynamic>> _courses = [];
  Map<String, dynamic> _options = const {};
  bool _loading = true;
  bool _failed = false;
  // The course a button is working on, so a second tap cannot fire the same step twice.
  int? _busyCourseId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final json = await api.teacherParcoursCourses(widget.parcoursId);
      if (!mounted) return;
      setState(() {
        _courses = (json['courses'] as List).cast<Map<String, dynamic>>();
        _options = (json['options'] as Map).cast<String, dynamic>();
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TeacherCourseCreateScreen(
          parcoursId: widget.parcoursId,
          parcoursName: widget.parcoursName,
          options: _options,
        ),
      ),
    );
    if (created == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Course « ${created['name']} » créée — code ${created['code']}.')),
    );
    await _load();
  }

  Future<void> _start(Map<String, dynamic> course) async {
    setState(() => _busyCourseId = course['id'] as int);
    await startCourse(context, course['id'] as int);
    if (!mounted) return;
    setState(() => _busyCourseId = null);
    await _load();
  }

  Future<void> _close(Map<String, dynamic> course) async {
    setState(() => _busyCourseId = course['id'] as int);
    await confirmAndCloseCourse(context, course['id'] as int, course['name'] as String);
    if (!mounted) return;
    setState(() => _busyCourseId = null);
    await _load();
  }

  void _follow(Map<String, dynamic> course) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => TeacherLiveScreen(courseId: course['id'] as int, courseName: course['name'] as String),
        ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EcoScreenHeader(
            title: widget.parcoursName,
            subtitle: 'Courses',
            trailing: _loading || _failed
                ? null
                : EcoHeaderBadge(
                    label: '${_courses.length}',
                    background: EcoColors.navyPill,
                    foreground: Colors.white,
                  ),
          ),
          TeacherParcoursLinks(parcoursId: widget.parcoursId, parcoursName: widget.parcoursName),
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
    if (_courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Aucune course sur ce parcours.\nCréez-en une : les coureurs la rejoindront avec son code, sans compte.",
            textAlign: TextAlign.center,
            style: EcoFont.sans(size: 14, color: EcoColors.muted, height: 1.4),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _courses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _courseCard(_courses[index]),
      ),
    );
  }

  Widget _courseCard(Map<String, dynamic> course) {
    final status = course['status'] as String? ?? 'prepared';
    final busy = _busyCourseId == course['id'];
    final runnerCount = (course['runnerCount'] as num?)?.toInt() ?? 0;
    final timeLimit = (course['timeLimitMinutes'] as num?)?.toInt();
    final details = <String>[
      course['modeLabel'] as String? ?? '',
      if (timeLimit != null) '$timeLimit min',
      if (runnerCount > 0) runnerCount > 1 ? '$runnerCount coureurs' : '1 coureur',
    ].where((part) => part.isNotEmpty);

    return EcoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderColor: status == 'in_progress' ? EcoColors.greenBorder : EcoColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(course['name'] as String, style: EcoFont.sans(size: 14.5, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              CourseStatusBadge(status: status, label: course['statusLabel'] as String? ?? status),
            ],
          ),
          const SizedBox(height: 3),
          Text(details.join(' · '), style: EcoFont.sans(size: 12, color: EcoColors.faint)),
          if (status != 'closed') ...[
            const SizedBox(height: 10),
            _code(course['code'] as String? ?? ''),
          ],
          if (status != 'closed') ...[
            const SizedBox(height: 12),
            _actions(course, status, busy),
          ],
        ],
      ),
    );
  }

  Widget _code(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: EcoColors.blueBgSoft, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text('Code de la course', style: EcoFont.sans(size: 11, color: EcoColors.muted)),
          Text(code, style: EcoFont.mono(size: 24, weight: FontWeight.w700, color: EcoColors.blueDark, letterSpacing: 6)),
        ],
      ),
    );
  }

  Widget _actions(Map<String, dynamic> course, String status, bool busy) {
    if (status == 'prepared') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: busy ? null : () => _start(course),
          style: ElevatedButton.styleFrom(backgroundColor: EcoColors.green, padding: const EdgeInsets.symmetric(vertical: 12)),
          icon: const Icon(Icons.play_arrow, size: 20),
          label: Text('Démarrer', style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: Colors.white)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _follow(course),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            icon: const Icon(Icons.podcasts, size: 18),
            label: Text('Suivre', style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: Colors.white)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _close(course),
            style: OutlinedButton.styleFrom(
              foregroundColor: EcoColors.red,
              side: const BorderSide(color: EcoColors.redBorder),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.stop, size: 18),
            label: Text('Arrêter', style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: EcoColors.red)),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: EcoColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 20),
            label: Text('Nouvelle course', style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
