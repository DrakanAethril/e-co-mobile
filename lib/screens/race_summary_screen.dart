import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/race_summary.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

/// What « Terminer » on the recap asks of the race screen underneath: leave the course.
const raceSummaryQuit = 'quit';

// The runner's recap, opened as soon as the finish is scanned: the time first, then what the phone
// and the server know about the run (distance, pace, climb, flags found, stops, refused scans), and
// the time of each leg. No rank: the race is still running for the others, and a position read at
// the finish would move under the runner's feet.
//
// Always read from the server (GET /api/eco/runner/summary), never worked out on the phone: the
// last positions queued before the finish reach the server a few seconds after it, so pulling down
// refreshes the figures.
class RaceSummaryScreen extends StatefulWidget {
  final String token;

  const RaceSummaryScreen({super.key, required this.token});

  @override
  State<RaceSummaryScreen> createState() => _RaceSummaryScreenState();
}

class _RaceSummaryScreenState extends State<RaceSummaryScreen> {
  RaceSummary? _summary;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final json = await context.read<ApiClient>().runnerSummary(widget.token);
      if (!mounted) return;
      setState(() {
        _summary = RaceSummary.fromJson(json);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      backgroundColor: EcoColors.bg,
      body: Column(
        children: [
          EcoScreenHeader(
            title: 'Course terminée',
            subtitle: summary == null
                ? null
                : [summary.parcoursName, summary.pseudo].where((part) => part.isNotEmpty).join(' · '),
          ),
          Expanded(
            child: summary != null
                ? RefreshIndicator(onRefresh: _load, child: _content(summary))
                : _placeholder(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(raceSummaryQuit),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text('Terminer', style: EcoFont.sans(size: 16, weight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _failed ? 'Récapitulatif indisponible hors réseau.' : 'Aucun récapitulatif.',
              textAlign: TextAlign.center,
              style: EcoFont.sans(size: 14, color: EcoColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }

  Widget _content(RaceSummary summary) {
    final found = summary.mode == 'imposed_order' ? 'Balises validées' : 'Balises trouvées';

    return ListView(
      padding: const EdgeInsets.all(16),
      // Pull-to-refresh needs a scrollable even when the recap fits the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _hero(summary),
        const SizedBox(height: 12),
        _tiles([
          _Tile('Distance', _kilometres(summary.distanceMeters)),
          _Tile('Vitesse moyenne', summary.averageSpeedKmh != null ? '${_decimal(summary.averageSpeedKmh!)} km/h' : '—'),
          _Tile(found, '${summary.checkpointsValidated}/${summary.checkpointsTotal}'),
          _Tile(
            'Dénivelé positif',
            summary.elevationGain != null ? '+${summary.elevationGain} m' : '—',
            note: summary.elevationSource == 'ign' ? 'Relief IGN' : (summary.elevationGain != null ? 'GPS du téléphone' : null),
          ),
          _Tile('Arrêts', summary.stopCount == 0 ? '0' : '${summary.stopCount} · ${_minutes(summary.stopSeconds)}'),
          _Tile('Scans refusés', '${summary.scanFailureCount}'),
        ]),
        if (summary.legs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _legs(summary.legs),
        ],
      ],
    );
  }

  Widget _hero(RaceSummary summary) {
    final finishedAt = summary.finishedAt?.toLocal();

    return EcoCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: EcoColors.green, size: 44),
          const SizedBox(height: 8),
          Text(
            summary.pseudo.isEmpty ? 'Bravo !' : 'Bravo, ${summary.pseudo} !',
            textAlign: TextAlign.center,
            style: EcoFont.spectral(size: 19),
          ),
          const SizedBox(height: 10),
          Text(_chrono(summary.durationSeconds), style: EcoFont.spectral(size: 40, color: EcoColors.navy, height: 1.1)),
          Text(
            finishedAt != null ? 'Temps de course · arrivée à ${_clock(finishedAt)}' : 'Temps de course',
            style: EcoFont.sans(size: 12, color: EcoColors.muted, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _tiles(List<_Tile> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: tiles.map((tile) => SizedBox(width: width, child: _tile(tile))).toList(),
        );
      },
    );
  }

  Widget _tile(_Tile tile) {
    return EcoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tile.label.toUpperCase(),
            style: EcoFont.sans(size: 10.5, weight: FontWeight.w600, color: EcoColors.faint, letterSpacing: 0.7),
          ),
          const SizedBox(height: 4),
          Text(tile.value, style: EcoFont.spectral(size: 22)),
          if (tile.note != null) Text(tile.note!, style: EcoFont.sans(size: 11, color: EcoColors.faint)),
        ],
      ),
    );
  }

  Widget _legs(List<RaceLeg> legs) {
    return EcoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TEMPS INTERMÉDIAIRES',
            style: EcoFont.sans(size: 11, weight: FontWeight.w600, color: EcoColors.faint, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          for (final (index, leg) in legs.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: index == 0 ? null : const Border(top: BorderSide(color: EcoColors.borderSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${leg.fromName} → ${leg.toName}',
                      style: EcoFont.sans(size: 13.5, weight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_kilometres(leg.distanceMeters), style: EcoFont.sans(size: 12.5, color: EcoColors.muted)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 54,
                    child: Text(
                      _chrono(leg.seconds),
                      textAlign: TextAlign.right,
                      style: EcoFont.mono(size: 13.5, color: EcoColors.blueDark),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// « 32:14 », or « 1:05:09 » past the hour.
  static String _chrono(int? seconds) {
    if (seconds == null) return '—';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');

    return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest' : '$minutes:$rest';
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  /// « 850 m » under a kilometre, « 2,4 km » above.
  static String _kilometres(int meters) => meters < 1000 ? '$meters m' : '${_decimal(meters / 1000)} km';

  static String _minutes(int seconds) => seconds < 60 ? '$seconds s' : '${(seconds / 60).round()} min';

  static String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
}

class _Tile {
  final String label;
  final String value;
  final String? note;

  _Tile(this.label, this.value, {this.note});
}
