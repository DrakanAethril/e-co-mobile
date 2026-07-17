import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/checkpoint.dart';
import '../models/runner_session.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/offline_queue_db.dart';
import '../services/queue_processor.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'join_screen.dart';
import 'map_screen.dart';
import 'scan_screen.dart';

// Unifies screens 1b (Ordre imposé) and 2b (Ordre libre) - same shell (chrono, progress, Scanner/
// Carte/Code balise/SOS), the only difference is whether the checkpoint area shows a single
// "prochaine balise" card or a free-choice grid (App\Enum\EcoCourseMode on the server).
class RaceScreen extends StatefulWidget {
  final RunnerSession session;
  const RaceScreen({super.key, required this.session});

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> with WidgetsBindingObserver {
  late RunnerSession _session;
  late final QueueProcessor _queueProcessor;
  Timer? _chronoTimer;
  Timer? _refreshTimer;
  Duration _elapsed = Duration.zero;
  String? _lastScanMessage;
  Color _lastScanColor = EcoColors.green;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    WidgetsBinding.instance.addObserver(this);

    final api = context.read<ApiClient>();
    final queueDb = context.read<OfflineQueueDb>();
    _queueProcessor = QueueProcessor(api, queueDb, () => _session.token);
    _queueProcessor.start();

    if (_session.status == 'racing') {
      context.read<LocationService>().startTracking();
    }

    _chronoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickChrono());
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refreshFromServer());
    _tickChrono();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chronoTimer?.cancel();
    _refreshTimer?.cancel();
    _queueProcessor.dispose();
    context.read<LocationService>().stopTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_session.status != 'racing') return;
    final queue = context.read<OfflineQueueDb>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      queue.enqueue('app_event', {'type': 'left'});
    } else if (state == AppLifecycleState.resumed) {
      queue.enqueue('app_event', {'type': 'returned'});
      _queueProcessor.flush();
      _refreshFromServer();
    }
  }

  void _tickChrono() {
    final startedAt = _session.startedAt;
    if (startedAt == null || !mounted) return;
    setState(() => _elapsed = DateTime.now().toUtc().difference(startedAt.toUtc()));
  }

  // Reconciles anything the app couldn't confirm synchronously (a scan made while offline) -
  // GET /api/eco/runner/state is always the source of truth, never the app's own optimistic guess.
  Future<void> _refreshFromServer() async {
    try {
      final api = context.read<ApiClient>();
      final json = await api.runnerState(_session.token);
      final refreshed = RunnerSession.fromJson(json);
      if (mounted) setState(() => _session = refreshed);
    } catch (_) {
      // Still offline - nothing to reconcile yet.
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(builder: (_) => ScanScreen(token: _session.token)),
    );
    if (result == null) return;

    if (result.queued) {
      setState(() {
        _lastScanMessage = 'Hors réseau — le scan sera vérifié à la reconnexion.';
        _lastScanColor = EcoColors.gold;
      });
      return;
    }

    setState(() {
      switch (result.result) {
        case 'success':
          _lastScanMessage = 'Balise validée${result.distanceMeters != null ? " — écart ${result.distanceMeters!.round()} m" : ""}';
          _lastScanColor = EcoColors.green;
          if (result.checkpointId != null) {
            _session = _session.copyWith(
              status: result.runnerStatus,
              startedAt: _session.startedAt ?? DateTime.now(),
              validatedCheckpointIds: {..._session.validatedCheckpointIds, result.checkpointId!}.toList(),
            );
          }
          break;
        case 'out_of_range':
          _lastScanMessage = 'Hors zone (> ${result.toleranceMeters ?? "?"} m)'
              '${result.distanceMeters != null ? " — écart mesuré ${result.distanceMeters!.round()} m" : ""}';
          _lastScanColor = EcoColors.red;
          break;
        case 'out_of_order':
          _lastScanMessage = "Balise hors séquence - respectez l'ordre imposé.";
          _lastScanColor = EcoColors.red;
          break;
      }
    });

    if (_session.status == 'racing') {
      context.read<LocationService>().startTracking();
    }
  }

  Future<void> _sos() async {
    final queue = context.read<OfflineQueueDb>();
    await queue.enqueue('sos', {});
    _queueProcessor.flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SOS envoyé.')));
  }

  Future<void> _quit() async {
    context.read<LocationService>().stopTracking();
    await context.read<SessionStore>().clearRunnerSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const JoinScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final validated = _session.validatedCheckpointIds.toSet();
    final regular = _session.checkpoints.where((c) => c.type == 'checkpoint').toList()..sort((a, b) => a.position.compareTo(b.position));
    final nextCheckpoint = regular.firstWhere((c) => !validated.contains(c.id), orElse: () => regular.isEmpty ? _finishCheckpoint() : regular.last);
    final finished = _session.status == 'finished';

    return Scaffold(
      body: Column(
        children: [
          _header(regular.length, validated.where((id) => regular.any((c) => c.id == id)).length),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (finished)
                    _finishedCard()
                  else if (_session.mode == 'imposed_order')
                    _nextCheckpointCard(nextCheckpoint)
                  else
                    _freeOrderGrid(regular, validated),
                  if (_lastScanMessage != null) ...[
                    const SizedBox(height: 12),
                    _feedbackBanner(),
                  ],
                  const Spacer(),
                  if (!finished) ...[
                    ElevatedButton(
                      onPressed: _scan,
                      child: const Text('Scanner la balise'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Screen 3f's own rule: no "Carte" button at all when the course is
                        // configured with mapVisibility "none".
                        if (_session.mapVisibility != 'none') ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => MapScreen(session: _session)),
                              ),
                              child: const Text('Carte'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        SizedBox(
                          width: 76,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: EcoColors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: _sos,
                            child: const Text('SOS'),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    OutlinedButton(onPressed: _quit, child: const Text('Terminer')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Checkpoint _finishCheckpoint() => _session.checkpoints.firstWhere((c) => c.type == 'finish');

  Widget _header(int totalCheckpoints, int validatedCount) {
    final minutes = _elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      color: EcoColors.navy,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/icons/eco/ic_launcher_96.png', width: 28, height: 28),
                const SizedBox(width: 9),
                Text(_session.courseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$minutes:$seconds', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600)),
                    const Text('Temps de course', style: TextStyle(color: Color(0xFF7D99B0), fontSize: 11)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$validatedCount/$totalCheckpoints', style: const TextStyle(color: EcoColors.gold, fontSize: 32, fontWeight: FontWeight.w600)),
                    const Text('Balises validées', style: TextStyle(color: Color(0xFF7D99B0), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextCheckpointCard(Checkpoint checkpoint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: EcoColors.border)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: const Color(0xFFDCEBF7), borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text('${checkpoint.position}', style: const TextStyle(color: EcoColors.blueDark, fontWeight: FontWeight.bold, fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PROCHAINE BALISE', style: TextStyle(color: EcoColors.faint, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(checkpoint.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _freeOrderGrid(List<Checkpoint> regular, Set<int> validated) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: EcoColors.border)),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: regular.map((c) {
          final done = validated.contains(c.id);
          return Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? const Color(0xFFE3EDE6) : Colors.transparent,
              border: Border.all(color: done ? const Color(0xFFCDE3D6) : const Color(0xFFB3C6D6), width: done ? 1 : 1.5, style: done ? BorderStyle.solid : BorderStyle.solid),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('${c.position}', style: TextStyle(fontWeight: FontWeight.bold, color: done ? const Color(0xFF25543C) : EcoColors.faint)),
          );
        }).toList(),
      ),
    );
  }

  Widget _finishedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: EcoColors.border)),
      child: const Column(
        children: [
          Icon(Icons.check_circle, color: EcoColors.green, size: 48),
          SizedBox(height: 10),
          Text('Course terminée', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _feedbackBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _lastScanColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(_lastScanMessage!, style: TextStyle(color: _lastScanColor, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
