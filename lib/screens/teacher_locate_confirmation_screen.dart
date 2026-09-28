import 'package:flutter/material.dart';

import '../theme.dart';

// Handoff screen 4c - what a teacher sees straight after scanning a checkpoint on the ground: a
// full screen rather than a dialog, so the fix that was just recorded (and how good it was) can be
// read at arm's length, in the field, before walking on to the next one.
class TeacherLocateConfirmationScreen extends StatelessWidget {
  final String parcoursName;
  final String checkpointName;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final int toleranceMeters;
  final int locatedCount;
  final int totalCount;

  /// The next checkpoint still to locate, if any: it turns the primary button into "Scanner la
  /// balise suivante (5)" instead of a dead end.
  final String? nextCheckpointLabel;

  /// The IGN's reading of the ground under the flag (LiDAR HD / RGE ALTI), read by the server as it
  /// saved the position. All three are null when the IGN did not answer in time: the position is
  /// saved all the same and the web screen's terrain analysis reads it later.
  final double? groundAltitude;
  final double? canopyHeight;

  /// A wider radius than the flag has, when the canopy calls for one - set on the web screen.
  final int? advisedToleranceMeters;

  const TeacherLocateConfirmationScreen({
    super.key,
    required this.parcoursName,
    required this.checkpointName,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.toleranceMeters,
    required this.locatedCount,
    required this.totalCount,
    this.nextCheckpointLabel,
    this.groundAltitude,
    this.canopyHeight,
    this.advisedToleranceMeters,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.navyDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF1C3346), EcoColors.navyDark],
          ),
        ),
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: EcoColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: EcoColors.green.withOpacity(0.25), width: 10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.check, color: Colors.white, size: 42),
                    ),
                    const SizedBox(height: 18),
                    Text('$checkpointName localisée', style: EcoFont.spectral(size: 24, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      'Position enregistrée pour le parcours',
                      style: EcoFont.sans(size: 13.5, color: EcoColors.onNavyMuted),
                    ),
                    const SizedBox(height: 18),
                    _detailsCard(),
                    if (advisedToleranceMeters != null) ...[
                      const SizedBox(height: 12),
                      _toleranceAdvice(advisedToleranceMeters!),
                    ],
                    const SizedBox(height: 18),
                    _offlineNote(),
                  ],
                ),
              ),
            ),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Localisation — $checkpointName',
                    style: EcoFont.spectral(size: 15, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    parcoursName,
                    style: EcoFont.sans(size: 11.5, color: EcoColors.onNavyMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _row(
            'Coordonnées',
            Text(
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
              style: EcoFont.mono(size: 13, color: const Color(0xFFCFDDE9)),
            ),
          ),
          _row(
            'Précision GPS',
            Text(
              '±${accuracyMeters.round()} m',
              style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: EcoColors.onNavyPositive),
            ),
          ),
          _row(
            'Tolérance course',
            Text(
              '$toleranceMeters m',
              style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: const Color(0xFFCFDDE9)),
            ),
          ),
          if (groundAltitude != null)
            _row(
              'Altitude (IGN)',
              Text(
                '${groundAltitude!.round()} m',
                style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: const Color(0xFFCFDDE9)),
              ),
            ),
          if (canopyHeight != null)
            _row(
              'Végétation autour',
              Text(
                canopyHeight! < 1 ? 'dégagé' : '${canopyHeight!.round()} m de haut',
                style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: const Color(0xFFCFDDE9)),
              ),
            ),
          _row(
            'Progression',
            Text(
              '$locatedCount/$totalCount localisées',
              style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: EcoColors.goldStrong),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: EcoFont.sans(size: 13, color: EcoColors.onNavyMuted)),
          value,
        ],
      ),
    );
  }

  /// Under a tall canopy a phone's fix wanders further: runners standing at the flag would be
  /// refused at the current radius. The mobile app does not edit tolerances, the web screen does.
  Widget _toleranceAdvice(int meters) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: EcoColors.gold.withOpacity(0.14),
        border: Border.all(color: EcoColors.gold.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Balise sous couvert végétal : une tolérance de $meters m est conseillée (réglable sur l’écran web du parcours).',
        style: EcoFont.sans(size: 12, color: EcoColors.goldStrong, height: 1.4),
      ),
    );
  }

  Widget _offlineNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: EcoColors.gold.withOpacity(0.14),
        border: Border.all(color: EcoColors.gold.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Hors réseau : la position est enregistrée sur le téléphone et sera synchronisée automatiquement.',
        style: EcoFont.sans(size: 12, color: EcoColors.goldStrong, height: 1.4),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final next = nextCheckpointLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (next != null) ...[
              ElevatedButton(
                // `true` tells the list screen to open the camera again straight away.
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Scanner la balise suivante ($next)',
                  style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.10),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'Retour à la liste',
                style: EcoFont.sans(size: 13.5, weight: FontWeight.w600, color: const Color(0xFFCFDDE9)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
