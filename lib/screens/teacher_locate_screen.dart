import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import 'teacher_scan_camera_screen.dart';

// Screens 4b (list) + 4c (confirmation) - the teacher walks to each checkpoint, scans its QR,
// this posts the current GPS fix via App\Controller\Api\EcoTeacherApiController::locate(). Unlike
// runner telemetry this isn't offline-queued: locating only ever happens with the teacher present
// and online, and re-scanning simply overwrites the previous position (EcoCheckpoint::locate()).
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

  Future<void> _scanCheckpoint(Map<String, dynamic> checkpoint) async {
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
      final api = context.read<ApiClient>();
      final json = await api.teacherLocateCheckpoint(widget.jwt, checkpoint['id'] as int, position.latitude, position.longitude);
      if (!mounted) return;
      await _showConfirmation(checkpoint['name'] as String, position, json);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Échec de l'enregistrement — vérifiez la connexion.")));
    }
  }

  // Screen 4c
  Future<void> _showConfirmation(String name, Position position, Map<String, dynamic> json) {
    final locatedCount = json['locatedCount'];
    final totalCount = json['totalCount'];
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EcoColors.navyDark,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 34, backgroundColor: EcoColors.green, child: Icon(Icons.check, color: Colors.white, size: 36)),
            const SizedBox(height: 14),
            Text('$name localisée', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  _confirmRow('Coordonnées', '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'),
                  _confirmRow('Précision GPS', '±${position.accuracy.round()} m'),
                  _confirmRow('Progression', '$locatedCount/$totalCount localisées'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF9FB5C8), fontSize: 13)),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.parcoursName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _checkpoints.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final c = _checkpoints[index];
                final located = c['located'] as bool;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: located ? EcoColors.border : EcoColors.gold, width: located ? 1 : 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: located ? const Color(0xFFE3EDE6) : const Color(0xFFFAF1DD), borderRadius: BorderRadius.circular(9)),
                        alignment: Alignment.center,
                        child: Text(_shortLabel(c), style: TextStyle(fontWeight: FontWeight.bold, color: located ? const Color(0xFF25543C) : const Color(0xFF9A7729))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              located ? '✓ ${(c['latitude'] as num).toStringAsFixed(4)}, ${(c['longitude'] as num).toStringAsFixed(4)}' : 'À localiser',
                              style: TextStyle(fontSize: 11.5, color: located ? const Color(0xFF25543C) : const Color(0xFF9A7729)),
                            ),
                          ],
                        ),
                      ),
                      if (located)
                        TextButton(onPressed: () => _scanCheckpoint(c), child: const Text('Re-scanner'))
                      else
                        ElevatedButton(onPressed: () => _scanCheckpoint(c), child: const Text('Scanner')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _shortLabel(Map<String, dynamic> c) {
    if (c['type'] == 'start') return 'D';
    if (c['type'] == 'finish') return 'A';
    return '${c['position']}';
  }
}
