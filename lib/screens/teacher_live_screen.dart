import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

// Handoff screen 4d - the mobile counterpart of the web live view (course_live.html.twig): the
// same App\Service\EcoLiveTrackingService-shaped rows, the same 10 s beat, and the same map above
// them - checkpoints as landmarks, one pill per runner at their last known position.
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
  List<Map<String, dynamic>> _checkpoints = [];
  String? _courseCode;
  int? _elapsedMinutes;
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
      setState(() {
        _runners = (json['runners'] as List).cast<Map<String, dynamic>>();
        _checkpoints = (json['checkpoints'] as List? ?? []).cast<Map<String, dynamic>>();
        _courseCode = json['courseCode'] as String?;
        _elapsedMinutes = (json['elapsedMinutes'] as num?)?.toInt();
      });
    } catch (_) {
      // Keep showing the last known state - the next tick retries.
    }
  }

  int get _racingCount => _runners.where((r) => r['mapState'] == 'racing').length;

  @override
  Widget build(BuildContext context) {
    final sosRunners = _runners.where((r) => r['sosActive'] == true).toList();

    return Scaffold(
      body: Column(
        children: [
          EcoScreenHeader(
            title: widget.courseName,
            subtitle: _subtitle(),
            trailing: EcoHeaderBadge(
              label: '$_racingCount en course',
              background: EcoColors.greenBg,
              foreground: EcoColors.greenTx,
            ),
          ),
          for (final runner in sosRunners) _sosStrip(runner),
          if (_checkpoints.isNotEmpty) SizedBox(height: 300, child: _map()),
          Expanded(
            child: _runners.isEmpty
                ? Center(child: Text('Aucun coureur pour le moment.', style: EcoFont.sans(size: 13, color: EcoColors.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: _runners.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, index) => _runnerTile(_runners[index]),
                  ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (_courseCode != null) _courseCode!,
      'en cours',
      if (_elapsedMinutes != null) '$_elapsedMinutes min',
    ];

    return parts.join(' · ');
  }

  Widget _sosStrip(Map<String, dynamic> runner) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: EcoColors.redBg,
        border: Border(bottom: BorderSide(color: EcoColors.redBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(color: EcoColors.red, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('!', style: EcoFont.sans(size: 11, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SOS — ${runner['pseudo']} · ${runner['signalLabel'] ?? ''}',
              style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: EcoColors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map() {
    final points = _checkpoints.map((c) => LatLng((c['latitude'] as num).toDouble(), (c['longitude'] as num).toDouble())).toList();

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40)),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.beaupeyrat.eco',
            ),
            MarkerLayer(markers: _checkpoints.map(_checkpointMarker).toList()),
            MarkerLayer(markers: _runners.where(_isOnMap).map(_runnerMarker).toList()),
          ],
        ),
        const EcoMapAttribution(trailing: '10 s'),
      ],
    );
  }

  bool _isOnMap(Map<String, dynamic> runner) =>
      runner['latitude'] != null && runner['longitude'] != null && runner['mapState'] != 'finished';

  Marker _checkpointMarker(Map<String, dynamic> checkpoint) {
    final isAnchor = checkpoint['type'] != 'checkpoint';

    return Marker(
      point: LatLng((checkpoint['latitude'] as num).toDouble(), (checkpoint['longitude'] as num).toDouble()),
      width: 30,
      height: 30,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isAnchor ? EcoColors.blueDark : Colors.white,
            shape: BoxShape.circle,
            border: isAnchor ? null : Border.all(color: EcoColors.faint, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            _checkpointLabel(checkpoint),
            style: EcoFont.sans(size: 10, weight: FontWeight.w700, color: isAnchor ? Colors.white : EcoColors.muted),
          ),
        ),
      ),
    );
  }

  /// Blue while everything is normal, gold on a stale signal, red on an SOS - the same three
  /// readings as the web live map, worded server-side so both say exactly the same thing.
  Marker _runnerMarker(Map<String, dynamic> runner) {
    final state = runner['mapState'] as String? ?? 'racing';
    final (background, foreground) = switch (state) {
      'sos' => (EcoColors.red, Colors.white),
      'stale' => (EcoColors.gold, EcoColors.navy),
      _ => (EcoColors.blue, Colors.white),
    };

    return Marker(
      point: LatLng((runner['latitude'] as num).toDouble(), (runner['longitude'] as num).toDouble()),
      width: 160,
      height: 26,
      alignment: Alignment.center,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (state == 'sos' ? EcoColors.red : EcoColors.navy).withOpacity(0.35),
                blurRadius: state == 'sos' ? 0 : 8,
                spreadRadius: state == 'sos' ? 4 : 0,
                offset: state == 'sos' ? Offset.zero : const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            runner['mapLabel'] as String? ?? runner['pseudo'] as String,
            style: EcoFont.sans(size: 10.5, weight: FontWeight.w700, color: foreground),
          ),
        ),
      ),
    );
  }

  Widget _runnerTile(Map<String, dynamic> runner) {
    final sos = runner['sosActive'] == true;
    final stale = runner['isStale'] == true && runner['status'] != 'finished';
    final finished = runner['status'] == 'finished';

    // Worded server-side by App\Service\EcoLiveTrackingService, like the web live screen: the
    // delay reads in the largest unit that stays legible ("il y a 18 min", not "il y a 1080s").
    // The raw seconds are still in the payload for an older app, hence the fallback.
    final signal = runner['signalLabel'] as String? ??
        (runner['lastSignalSeconds'] != null ? 'il y a ${runner['lastSignalSeconds']}s' : '—');

    return EcoCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      background: sos ? EcoColors.redBg : (stale ? EcoColors.goldBg : Colors.white),
      borderColor: sos ? EcoColors.redBorder : (stale ? EcoColors.goldBorder : EcoColors.border),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${runner['pseudo']}${sos ? " 🆘" : ""}',
                  style: EcoFont.sans(
                    size: 13.5,
                    weight: sos || stale ? FontWeight.w700 : FontWeight.w600,
                    color: sos ? EcoColors.red : (stale ? EcoColors.goldTx : EcoColors.ink),
                  ),
                ),
                Text(
                  finished
                      ? '✓ Arrivée'
                      : '${runner['checkpointsValidated']}/${runner['checkpointsTotal']} · $signal',
                  style: EcoFont.sans(
                    size: 11.5,
                    color: sos ? EcoColors.red : (stale ? EcoColors.goldTx : (finished ? EcoColors.greenTx : EcoColors.faint)),
                  ),
                ),
              ],
            ),
          ),
          if (finished)
            Text('terminé', style: EcoFont.sans(size: 11.5, weight: FontWeight.w600, color: EcoColors.greenTx))
          else if (!sos && !stale)
            Text('en course', style: EcoFont.sans(size: 11.5, color: EcoColors.faint)),
        ],
      ),
    );
  }

  String _checkpointLabel(Map<String, dynamic> checkpoint) {
    if (checkpoint['type'] == 'start') return 'D';
    if (checkpoint['type'] == 'finish') return 'A';

    return '${checkpoint['position']}';
  }
}
