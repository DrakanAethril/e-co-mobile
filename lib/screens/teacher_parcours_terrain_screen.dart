import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_ign_map.dart';
import '../widgets/eco_widgets.dart';

// The web's « Lecture du terrain (IGN) » card on the phone: where the parcours is, the map of its
// located flags on the IGN's base map, the legs as the ground makes them (straight line, by the paths, climb, steepest stretch, wood, effort) and the
// safety sheet of every located flag. The reading is written by app:eco:read-terrain on the server,
// never here: « Analyser le terrain » only asks, and the screen polls until the answer is written.
class TeacherParcoursTerrainScreen extends StatefulWidget {
  final int parcoursId;
  final String parcoursName;

  /// How often a pending analysis is looked at again. Shortened by the tests.
  final Duration pollInterval;

  const TeacherParcoursTerrainScreen({
    super.key,
    required this.parcoursId,
    required this.parcoursName,
    this.pollInterval = const Duration(seconds: 5),
  });

  @override
  State<TeacherParcoursTerrainScreen> createState() => _TeacherParcoursTerrainScreenState();
}

class _TeacherParcoursTerrainScreenState extends State<TeacherParcoursTerrainScreen> {
  Map<String, dynamic>? _sheet;
  bool _failed = false;
  bool _requesting = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _show(await context.read<ApiClient>().teacherParcoursTerrain(widget.parcoursId));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _show(Map<String, dynamic> sheet) {
    if (!mounted) return;
    setState(() {
      _sheet = sheet;
      _failed = false;
    });
    _poll?.cancel();
    if (sheet['pending'] == true) {
      _poll = Timer(widget.pollInterval, _load);
    }
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      _show(await context.read<ApiClient>().teacherRequestTerrain(widget.parcoursId));
      messenger.showSnackBar(const SnackBar(content: Text("L'analyse du terrain est demandée : elle sera prête d'ici une à deux minutes.")));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Demande impossible — vérifiez la connexion.')));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.bg,
      body: Column(
        children: [
          EcoScreenHeader(title: widget.parcoursName, subtitle: 'Lecture du terrain (IGN)'),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final sheet = _sheet;
    if (sheet == null) {
      if (!_failed) return const Center(child: CircularProgressIndicator());

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

    final analysis = sheet['analysis'] is Map ? (sheet['analysis'] as Map).cast<String, dynamic>() : null;
    // Where the flags stand now, analysed or not: the map needs nothing the IGN has to answer.
    final flags = (sheet['flags'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _statusCard(sheet, analysis != null),
          if (analysis != null) ..._analysis(analysis, flags) else ..._map(flags),
          const SizedBox(height: 12),
          Text(
            "Données IGN – Géoplateforme (BD TOPO, RGE ALTI, LiDAR HD), Licence Ouverte Etalab 2.0. "
            "Les distances de la fiche sécurité sont à vol d'oiseau depuis chaque balise.",
            style: EcoFont.sans(size: 11.5, color: EcoColors.faint, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(Map<String, dynamic> sheet, bool hasAnalysis) {
    final pending = sheet['pending'] == true;
    final analyzedAt = DateTime.tryParse(sheet['analyzedAt'] as String? ?? '')?.toLocal();
    final stale = hasAnalysis && sheet['current'] != true;

    final String status;
    if (pending) {
      status = "Analyse en cours auprès de l'IGN… l'écran se met à jour de lui-même.";
    } else if (hasAnalysis && analyzedAt != null) {
      status = 'Analysé le ${_date(analyzedAt)}';
    } else {
      status = "Pas encore analysé : relief, chemins, forêt et accès des secours, d'après les données de l'IGN.";
    }

    return EcoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (pending) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(status, style: EcoFont.sans(size: 13, color: EcoColors.muted, height: 1.35))),
            ],
          ),
          if (stale && !pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Une balise a été déplacée depuis, relancez l’analyse.',
                style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: EcoColors.goldTx),
              ),
            ),
          if (sheet['canAnalyze'] == true) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _requesting ? null : _request,
              icon: const Icon(Icons.landscape_outlined, size: 18),
              label: Text(hasAnalysis ? "Relancer l'analyse" : 'Analyser le terrain'),
            ),
          ] else if (!pending && !hasAnalysis)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "Localisez au moins une balise pour que l'IGN puisse lire le terrain.",
                style: EcoFont.sans(size: 12, color: EcoColors.faint),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _analysis(Map<String, dynamic> analysis, List<Map<String, dynamic>> flags) {
    final commune = analysis['commune'] as String?;
    final nearby = analysis['nearbyPlace'] as String?;
    final forests = (analysis['publicForests'] as List? ?? []).cast<String>();
    final legs = (analysis['legs'] as List? ?? []).cast<Map<String, dynamic>>();
    final checkpoints = (analysis['checkpoints'] as List? ?? []).cast<Map<String, dynamic>>();
    final place = [
      if (commune != null) commune,
      if (nearby != null) 'près de « $nearby »',
    ].join(' · ');

    return [
      if (place.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text.rich(TextSpan(
          text: 'Lieu : ',
          style: EcoFont.sans(size: 13, color: EcoColors.faint),
          children: [TextSpan(text: place, style: EcoFont.sans(size: 13, weight: FontWeight.w600))],
        )),
      ],
      if (forests.isNotEmpty) ...[
        const SizedBox(height: 10),
        _note(
          '🌲',
          'Le parcours passe en forêt publique (${forests.join(', ')}) : une course organisée y demande '
              "l'accord de son gestionnaire (ONF ou collectivité propriétaire).",
          gold: true,
        ),
      ],
      if (analysis['incomplete'] == true) ...[
        const SizedBox(height: 10),
        _note('ℹ', "Analyse incomplète : l'IGN n'a pas répondu pour une partie des tronçons. Relancez-la plus tard."),
      ],
      ..._map(flags),
      if (legs.isNotEmpty) ...[
        _sectionTitle('TRONÇONS'),
        for (final leg in legs) ...[_legCard(leg), const SizedBox(height: 8)],
      ],
      if (checkpoints.isNotEmpty) ...[
        _sectionTitle('FICHE SÉCURITÉ'),
        EcoCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(
            children: [
              for (final (index, checkpoint) in checkpoints.indexed) _safetyRow(checkpoint, first: index == 0),
            ],
          ),
        ),
      ],
    ];
  }

  /// The parcours on the Plan IGN (or whichever layer the phone last chose), framed on its flags.
  /// Rotation is off: a map turned by a stray two-finger gesture no longer reads north-up.
  List<Widget> _map(List<Map<String, dynamic>> flags) {
    if (flags.isEmpty) return const [];

    final points = flags.map(_pointOf).toList();

    return [
      _sectionTitle('CARTE DU PARCOURS'),
      Container(
        height: 280,
        decoration: BoxDecoration(
          border: Border.all(color: EcoColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: EcoIgnMap(
          options: MapOptions(
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            // A lone flag would otherwise be framed at the deepest zoom, with nothing around it.
            initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 17),
          ),
          children: [
            MarkerLayer(markers: [for (final flag in flags) _flagMarker(flag)]),
          ],
        ),
      ),
    ];
  }

  static LatLng _pointOf(Map<String, dynamic> flag) =>
      LatLng((flag['latitude'] as num).toDouble(), (flag['longitude'] as num).toDouble());

  /// Start and finish filled, the flags in between outlined - the live map's markers, so a
  /// teacher reads the two maps the same way.
  Marker _flagMarker(Map<String, dynamic> flag) {
    final isAnchor = flag['type'] != 'checkpoint';

    return Marker(
      point: _pointOf(flag),
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
            '${flag['label']}',
            style: EcoFont.sans(size: 10, weight: FontWeight.w700, color: isAnchor ? Colors.white : EcoColors.muted),
          ),
        ),
      ),
    );
  }

  Widget _legCard(Map<String, dynamic> leg) {
    final ratio = _number(leg['pathRatio']);
    final slope = _number(leg['maxSlopePercent']);
    final climb = _number(leg['climbMeters']);
    final descent = _number(leg['descentMeters']);
    final forest = _number(leg['forestShare']);
    final effort = _number(leg['effortKm']);

    return EcoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${leg['fromLabel']} → ${leg['toLabel']}', style: EcoFont.spectral(size: 16)),
          const SizedBox(height: 6),
          _figure('Ligne droite', _meters(leg['straightMeters'])),
          _figure(
            'Par les chemins',
            _meters(leg['pathMeters']) + (ratio != null ? ' (×${_decimal(ratio)})' : ''),
            // Far longer by the paths: the leg is navigated across country, or not at all.
            tone: ratio != null && ratio >= 2 ? EcoColors.goldTx : null,
          ),
          _figure('Montée / descente', climb == null ? '—' : '+${climb.round()} / −${(descent ?? 0).round()} m'),
          _figure(
            'Pente max.',
            slope == null ? '—' : '${slope.round()} %',
            tone: slope == null ? null : (slope >= 30 ? EcoColors.red : (slope >= 15 ? EcoColors.goldTx : null)),
          ),
          _figure('En forêt', forest == null ? '—' : '${(forest * 100).round()} %'),
          _figure('Effort', effort == null ? '—' : '${effort.toStringAsFixed(2).replaceAll('.', ',')} km-e'),
        ],
      ),
    );
  }

  Widget _safetyRow(Map<String, dynamic> checkpoint, {required bool first}) {
    final road = _number(checkpoint['nearestCarRoadMeters']);
    final water = _number(checkpoint['nearestWaterMeters']);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: EcoColors.borderSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: EcoColors.blueBg, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text('${checkpoint['label']}', style: EcoFont.spectral(size: 13, weight: FontWeight.w700, color: EcoColors.blueDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${checkpoint['name']}', style: EcoFont.sans(size: 13.5, weight: FontWeight.w600)),
                _figure('Altitude', _meters(checkpoint['groundAltitude'])),
                _figure('Végétation', _meters(checkpoint['canopyHeight'])),
                // Past 500 m from a road a stretcher is carried a long way: worth planning.
                _figure('Route carrossable', _meters(road), tone: road != null && road >= 500 ? EcoColors.goldTx : null),
                _figure("Cours d'eau / plan d'eau", _meters(water), tone: water != null && water < 30 ? EcoColors.goldTx : null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, {Color? tone}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: EcoFont.sans(size: 12.5, color: EcoColors.muted))),
          Text(
            value,
            style: EcoFont.sans(size: 13, weight: tone != null ? FontWeight.w700 : FontWeight.w600, color: tone ?? EcoColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(title, style: EcoFont.sans(size: 11, weight: FontWeight.w600, color: EcoColors.faint, letterSpacing: 0.8)),
      );

  Widget _note(String icon, String text, {bool gold = false}) {
    return EcoCard(
      background: gold ? EcoColors.goldBg : EcoColors.blueBgSoft,
      borderColor: gold ? EcoColors.goldBorder : EcoColors.border,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: EcoFont.sans(size: 12.5, color: gold ? EcoColors.goldTx : EcoColors.muted, height: 1.4))),
        ],
      ),
    );
  }

  static double? _number(Object? value) => value is num ? value.toDouble() : null;

  static String _meters(Object? value) {
    final meters = _number(value);

    return meters == null ? '—' : '${meters.round()} m';
  }

  static String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

  static String _date(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(at.day)}/${two(at.month)}/${at.year} ${two(at.hour)}:${two(at.minute)}';
  }
}
