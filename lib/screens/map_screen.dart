import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/checkpoint.dart';
import '../models/runner_session.dart';
import '../theme.dart';

// Screen 3f - checkpoint map. The runner's own position is deliberately never plotted here (see
// e-CO.dc.html's "Votre position n'apparaît pas sur la carte" note); which checkpoints even have
// coordinates to show is decided server-side per EcoCourse::$mapVisibility, not filtered here.
class MapScreen extends StatelessWidget {
  final RunnerSession session;
  const MapScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final validated = session.validatedCheckpointIds.toSet();
    final visible = session.checkpoints.where((c) => c.hasCoordinates).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Carte du parcours')),
      body: Column(
        children: [
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("Carte indisponible pour l'instant.", textAlign: TextAlign.center)))
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(visible.first.latitude!, visible.first.longitude!),
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.beaupeyrat.eco',
                      ),
                      MarkerLayer(
                        markers: visible.map((c) => _markerFor(c, validated)).toList(),
                      ),
                    ],
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: const Color(0xFFEEF5FB),
            child: const Text(
              "🧭 Votre position n'apparaît pas sur la carte : à vous de vous orienter !",
              style: TextStyle(color: EcoColors.blueDark, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Marker _markerFor(Checkpoint checkpoint, Set<int> validated) {
    final isValidated = validated.contains(checkpoint.id);
    final isBoundary = checkpoint.type != 'checkpoint';
    final color = isBoundary ? EcoColors.blueDark : (isValidated ? EcoColors.green : EcoColors.faint);
    final label = checkpoint.type == 'start' ? 'D' : (checkpoint.type == 'finish' ? 'A' : '${checkpoint.position}');

    return Marker(
      point: LatLng(checkpoint.latitude!, checkpoint.longitude!),
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}
