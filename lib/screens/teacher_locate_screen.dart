import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';
import 'teacher_locate_confirmation_screen.dart';
import 'teacher_scan_camera_screen.dart';

// Handoff screen 4b - the teacher walks to each checkpoint, scans its QR, and this posts the
// current GPS fix via App\Controller\Api\EcoTeacherApiController::locate(). Unlike runner telemetry
// this isn't offline-queued: locating only ever happens with the teacher present and online, and
// re-scanning simply overwrites the previous position (EcoCheckpoint::locate()).
class TeacherLocateScreen extends StatefulWidget {
  final String jwt;
  final int parcoursId;
  final String parcoursName;
  const TeacherLocateScreen({super.key, required this.jwt, required this.parcoursId, required this.parcoursName});

  @override
  State<TeacherLocateScreen> createState() => _TeacherLocateScreenState();
}

class _TeacherLocateScreenState extends State<TeacherLocateScreen> {
  List<Map<String, dynamic>> _checkpoints = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final json = await api.teacherParcoursShow(widget.jwt, widget.parcoursId);
    if (!mounted) return;
    setState(() {
      _checkpoints = (json['checkpoints'] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  int get _locatedCount => _checkpoints.where((c) => c['located'] == true).length;

  /// The first checkpoint still without a position - what both the bottom button and the
  /// confirmation screen's "balise suivante" point at.
  Map<String, dynamic>? get _nextToLocate {
    for (final checkpoint in _checkpoints) {
      if (checkpoint['located'] != true) return checkpoint;
    }

    return null;
  }

  Future<void> _scanCheckpoint(Map<String, dynamic> checkpoint) async {
    // Read off the provider before the first await: the widget can be gone by the time the camera
    // and the GPS have both answered.
    final api = context.read<ApiClient>();
    final shortCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const TeacherScanCameraScreen()),
    );
    if (shortCode == null) return;
    if (shortCode.toUpperCase() != (checkpoint['shortCode'] as String).toUpperCase()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('QR scanné (${shortCode.toUpperCase()}) ne correspond pas à la balise ${checkpoint['name']}.')));
      return;
    }

    Position? position;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Position GPS indisponible.')));
      return;
    }

    try {
      final json = await api.teacherLocateCheckpoint(widget.jwt, checkpoint['id'] as int, position.latitude, position.longitude);
      // What the server read from the IGN for this spot - absent when the IGN was too slow to answer.
      final located = json['checkpoint'] is Map ? (json['checkpoint'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      if (!mounted) return;
      await _load();
      if (!mounted) return;

      final next = _nextToLocate;
      final scanNext = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TeacherLocateConfirmationScreen(
            parcoursName: widget.parcoursName,
            checkpointName: checkpoint['name'] as String,
            latitude: position!.latitude,
            longitude: position.longitude,
            accuracyMeters: position.accuracy,
            toleranceMeters: (checkpoint['toleranceMeters'] as num?)?.toInt() ?? 20,
            locatedCount: (json['locatedCount'] as num).toInt(),
            totalCount: (json['totalCount'] as num).toInt(),
            nextCheckpointLabel: next != null ? _shortLabel(next) : null,
            groundAltitude: (located['groundAltitude'] as num?)?.toDouble(),
            canopyHeight: (located['canopyHeight'] as num?)?.toDouble(),
            advisedToleranceMeters: (located['advisedToleranceMeters'] as num?)?.toInt(),
          ),
        ),
      );

      if (scanNext == true && next != null && mounted) {
        await _scanCheckpoint(next);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec de l'enregistrement — vérifiez la connexion.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _checkpoints.length;
    final located = _locatedCount;
    final next = _nextToLocate;

    return Scaffold(
      body: Column(
        children: [
          EcoScreenHeader(
            title: widget.parcoursName,
            subtitle: 'Localisation des balises',
            trailing: total == 0
                ? null
                : EcoHeaderBadge(
                    label: '$located/$total',
                    background: located == total ? EcoColors.greenBg : EcoColors.goldBg,
                    foreground: located == total ? EcoColors.greenTx : EcoColors.goldTx,
                  ),
          ),
          if (!_loading && total > 0) _progress(located, total),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _checkpoints.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _checkpointTile(_checkpoints[index]),
                  ),
          ),
          if (next != null) _bottomBar(next),
        ],
      ),
    );
  }

  Widget _progress(int located, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : located / total,
              minHeight: 7,
              backgroundColor: EcoColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(EcoColors.gold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Posez chaque balise à l'endroit voulu puis scannez son QR pour enregistrer sa position. "
            'Re-scanner une balise met à jour sa position.',
            style: EcoFont.sans(size: 12, color: EcoColors.faint, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _checkpointTile(Map<String, dynamic> checkpoint) {
    final located = checkpoint['located'] == true;
    final tolerance = (checkpoint['toleranceMeters'] as num?)?.toInt();
    final note = checkpoint['note'] as String?;

    // The mockup spells out what makes a checkpoint special right next to its name: a landmark
    // note, and a tolerance that was widened away from the parcours default.
    // The IGN's advice rides along once it has read the ground under the flag: a canopy calling
    // for a wider radius than the flag has.
    final advised = (checkpoint['advisedToleranceMeters'] as num?)?.toInt();
    final qualifiers = <String>[
      if (note != null && note.isNotEmpty) note,
      if (tolerance != null && tolerance != 20) 'tol. $tolerance m',
      if (advised != null) 'tol. conseillée $advised m',
    ];

    return EcoCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: located ? EcoColors.border : EcoColors.gold,
      borderWidth: located ? 1 : 1.5,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _badgeBackground(checkpoint, located),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              _shortLabel(checkpoint),
              style: EcoFont.spectral(size: 15, weight: FontWeight.w700, color: _badgeForeground(checkpoint, located)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: checkpoint['name'] as String,
                    style: EcoFont.sans(size: 14, weight: FontWeight.w600),
                    children: [
                      if (qualifiers.isNotEmpty)
                        TextSpan(
                          text: ' (${qualifiers.join(' · ')})',
                          style: EcoFont.sans(size: 11.5, color: EcoColors.faint),
                        ),
                    ],
                  ),
                ),
                Text(
                  located ? _locatedLabel(checkpoint) : 'À localiser',
                  style: EcoFont.sans(size: 11.5, color: located ? EcoColors.greenTx : EcoColors.goldTx),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (located)
            TextButton(
              onPressed: () => _scanCheckpoint(checkpoint),
              style: TextButton.styleFrom(foregroundColor: EcoColors.faint, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text('Re-scanner', style: EcoFont.sans(size: 12, weight: FontWeight.w600, color: EcoColors.faint)),
            )
          else
            ElevatedButton(
              onPressed: () => _scanCheckpoint(checkpoint),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
              child: Text('Scanner', style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(Map<String, dynamic> next) {
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
          child: ElevatedButton(
            onPressed: () => _scanCheckpoint(next),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EcoQrGlyph(size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'Scanner la prochaine balise',
                  style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _locatedLabel(Map<String, dynamic> checkpoint) {
    final latitude = (checkpoint['latitude'] as num).toStringAsFixed(4);
    final longitude = (checkpoint['longitude'] as num).toStringAsFixed(4);
    final locatedAt = checkpoint['locatedAt'] as String?;
    if (locatedAt == null) return '✓ $latitude, $longitude';

    final at = DateTime.tryParse(locatedAt)?.toLocal();
    if (at == null) return '✓ $latitude, $longitude';

    final day = '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

    return '✓ $latitude, $longitude · $day $time';
  }

  Color _badgeBackground(Map<String, dynamic> checkpoint, bool located) {
    if (checkpoint['type'] != 'checkpoint') return EcoColors.blueBg;

    return located ? EcoColors.greenBg : EcoColors.goldBg;
  }

  Color _badgeForeground(Map<String, dynamic> checkpoint, bool located) {
    if (checkpoint['type'] != 'checkpoint') return EcoColors.blueDark;

    return located ? EcoColors.greenTx : EcoColors.goldTx;
  }

  String _shortLabel(Map<String, dynamic> checkpoint) {
    if (checkpoint['type'] == 'start') return 'D';
    if (checkpoint['type'] == 'finish') return 'A';

    return '${checkpoint['position']}';
  }
}
