import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';

// Screen 4d - mobile equivalent of the web live view (course_live.html.twig): same
// App\Service\EcoLiveTrackingService-shaped rows, polled every ~10s.
class TeacherLiveScreen extends StatefulWidget {
  final String jwt;
  final int courseId;
  final String courseName;
  const TeacherLiveScreen({super.key, required this.jwt, required this.courseId, required this.courseName});

  @override
  State<TeacherLiveScreen> createState() => _TeacherLiveScreenState();
}

class _TeacherLiveScreenState extends State<TeacherLiveScreen> {
  List<Map<String, dynamic>> _runners = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final api = context.read<ApiClient>();
      final json = await api.teacherCourseLive(widget.jwt, widget.courseId);
      if (!mounted) return;
      setState(() => _runners = (json['runners'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // Keep showing the last known state - the next tick retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sosRunners = _runners.where((r) => r['sosActive'] == true).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.courseName)),
      body: Column(
        children: [
          if (sosRunners.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFFFBECEB),
              padding: const EdgeInsets.all(12),
              child: Text(
                'SOS — ${sosRunners.map((r) => r['pseudo']).join(', ')}',
                style: const TextStyle(color: EcoColors.red, fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(
            child: _runners.isEmpty
                ? const Center(child: Text('Aucun coureur pour le moment.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _runners.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _runnerTile(_runners[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _runnerTile(Map<String, dynamic> runner) {
    final sos = runner['sosActive'] == true;
    final stale = runner['isStale'] == true && runner['status'] != 'finished';
    final bg = sos ? const Color(0xFFFBECEB) : (stale ? const Color(0xFFFAF1DD) : Colors.white);
    final border = sos ? const Color(0xFFECC4BD) : (stale ? const Color(0xFFECD9AD) : EcoColors.border);

    String signal;
    if (runner['appLeftSeconds'] != null) {
      signal = 'hors app · il y a ${runner['appLeftSeconds']}s';
    } else if (runner['lastSignalSeconds'] != null) {
      signal = 'il y a ${runner['lastSignalSeconds']}s';
    } else {
      signal = '—';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${runner['pseudo']}${sos ? " 🆘" : ""}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  runner['status'] == 'finished' ? '✓ Arrivée' : '${runner['checkpointsValidated']}/${runner['checkpointsTotal']} · $signal',
                  style: TextStyle(fontSize: 12, color: sos ? EcoColors.red : (stale ? const Color(0xFF9A7729) : EcoColors.faint)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
