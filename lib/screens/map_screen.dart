import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/checkpoint.dart';
import '../models/runner_session.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

// Handoff screen 3f - the checkpoint map. The runner's own position is deliberately never plotted
// here (see the crea's "Votre position n'apparaît pas sur la carte" note); which checkpoints even
// have coordinates to show is decided server-side per EcoCourse::$mapVisibility, not filtered here.
class MapScreen extends StatelessWidget {
  final RunnerSession session;

  /// The chrono is carried over from the race screen so the header keeps counting while the map is
  /// open, rather than restarting from zero.
  final Duration elapsed;

  const MapScreen({super.key, required this.session, this.elapsed = Duration.zero});

  @override
  Widget build(BuildContext context) {
    final validated = session.validatedCheckpointIds.toSet();
    final regular = session.checkpoints.where((c) => c.type == 'checkpoint');
    final validatedCount = regular.where((c) => validated.contains(c.id)).length;
    final visible = session.checkpoints.where((c) => c.hasCoordinates).toList();

    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      body: Column(
        children: [
          EcoScreenHeader(
            title: 'Carte du parcours',
            subtitle: session.parcoursName.isEmpty
                ? '$validatedCount/${regular.length} validées'
                : '${session.parcoursName} · $validatedCount/${regular.length} validées',
            trailing: Text('$minutes:$seconds', style: EcoFont.spectral(size: 22, color: EcoColors.gold)),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "Carte indisponible pour l'instant.",
                        textAlign: TextAlign.center,
                        style: EcoFont.sans(size: 13, color: EcoColors.muted),
                      ),
                    ),
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: visible.map((c) => LatLng(c.latitude!, c.longitude!)).toList(),
                        padding: const EdgeInsets.all(48),
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.beaupeyrat.eco',
                      ),
                      MarkerLayer(markers: visible.map((c) => _markerFor(c, validated)).toList()),
                    ],
                  ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendItem(color: EcoColors.green, label: 'Validée'),
                _LegendItem(color: EcoColors.gold, label: 'Prochaine'),
                _LegendItem(color: EcoColors.faint, label: 'À trouver', dashed: true),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: EcoColors.blueBgSoft,
                border: Border.all(color: const Color(0xFFC6DDF0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "🧭 Votre position n'apparaît pas sur la carte : à vous de vous orienter !",
                style: EcoFont.sans(size: 11.5, weight: FontWeight.w600, color: EcoColors.blueDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Départ and Arrivée keep the navy of the anchors; a numbered checkpoint reads green once
  /// validated, gold and larger while it is the next one, and dashed grey until then.
  Marker _markerFor(Checkpoint checkpoint, Set<int> validated) {
    final isAnchor = checkpoint.type != 'checkpoint';
    final isValidated = validated.contains(checkpoint.id);
    final isNext = checkpoint.isNext && !isValidated;
    final size = isNext ? 36.0 : 32.0;

    final BoxDecoration decoration;
    final Color textColor;
    if (isAnchor) {
      decoration = BoxDecoration(
        color: EcoColors.blueDark,
        shape: BoxShape.circle,
        border: Border.all(color: EcoColors.blueDark.withOpacity(0.22), width: 4),
      );
      textColor = Colors.white;
    } else if (isValidated) {
      decoration = const BoxDecoration(color: EcoColors.green, shape: BoxShape.circle);
      textColor = Colors.white;
    } else if (isNext) {
      decoration = BoxDecoration(
        color: EcoColors.gold,
        shape: BoxShape.circle,
        border: Border.all(color: EcoColors.gold.withOpacity(0.32), width: 5),
        boxShadow: [BoxShadow(color: const Color(0xFF7A5417).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
      );
      textColor = EcoColors.navy;
    } else {
      decoration = BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: EcoColors.faint, width: 2),
      );
      textColor = EcoColors.muted;
    }

    return Marker(
      point: LatLng(checkpoint.latitude!, checkpoint.longitude!),
      width: size + 12,
      height: size + 12,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: decoration,
          alignment: Alignment.center,
          child: Text(
            checkpoint.shortLabel,
            style: EcoFont.sans(size: isNext ? 14 : 12, weight: FontWeight.w700, color: textColor),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _LegendItem({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: dashed ? Border.all(color: color, width: 2) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: EcoFont.sans(size: 11.5, weight: FontWeight.w600, color: EcoColors.muted)),
      ],
    );
  }
}
