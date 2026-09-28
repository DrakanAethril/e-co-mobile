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
import '../widgets/eco_widgets.dart';
import 'join_screen.dart';
import 'map_screen.dart';
import 'race_summary_screen.dart';
import 'scan_screen.dart';

// Handoff screens 1b (Ordre imposé) and 2b (Ordre libre): one shell - navy header with the
// chrono, the progress and the gold bar, then the checkpoint area, then Scanner and the
// Carte / Code balise / SOS row. The mode only changes the middle area and what the header counts:
// elapsed time and validated checkpoints in imposed order, time left and checkpoints found
// otherwise.
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
  _FeedbackTone _lastScanTone = _FeedbackTone.success;
  bool _online = true;
  // The recap opens by itself once, the moment the finish is known - scanned here or confirmed
  // by a refresh after an offline scan. Relaunching on a finished race does not reopen it: the
  // finished card carries the button.
  bool _summaryOpened = false;

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
    // Past the finish the chrono stops on the race's time instead of running on behind the recap.
    final end = _session.finishedAt ?? DateTime.now();
    setState(() => _elapsed = end.toUtc().difference(startedAt.toUtc()));
  }

  // Reconciles anything the app couldn't confirm synchronously (a scan made while offline) -
  // GET /api/eco/runner/state is always the source of truth, never the app's own optimistic guess.
  // Whether it succeeds is also what the "En ligne / Hors reseau" pill reports.
  Future<void> _refreshFromServer() async {
    try {
      final api = context.read<ApiClient>();
      final json = await api.runnerState(_session.token);
      final refreshed = RunnerSession.fromJson(json);
      final justFinished = _session.status != 'finished' && refreshed.status == 'finished';
      if (mounted) {
        setState(() {
          _session = refreshed;
          _online = true;
        });
        if (justFinished) _onFinished();
      }
    } catch (_) {
      if (mounted) setState(() => _online = false);
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(builder: (_) => ScanScreen(token: _session.token, checkpointLabel: _promptLabel())),
    );
    _handleScanResult(result);
  }

  /// "Code balise" opens the same screen as "Scanner", straight onto manual entry: it is the same
  /// business gesture, only the QR reading is short-circuited.
  Future<void> _scanByCode() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(token: _session.token, checkpointLabel: _promptLabel(), openManualEntry: true),
      ),
    );
    _handleScanResult(result);
  }

  void _handleScanResult(ScanResult? result) {
    if (result == null || !mounted) return;

    if (result.queued) {
      setState(() {
        _lastScanMessage = 'Hors réseau — le scan sera vérifié à la reconnexion.';
        _lastScanTone = _FeedbackTone.pending;
        _online = false;
      });
      return;
    }

    setState(() {
      _online = true;
      switch (result.result) {
        case 'success':
          final at = TimeOfDay.now();
          final gap = result.distanceMeters != null ? ' — écart ${result.distanceMeters!.round()} m' : '';
          _lastScanMessage = 'Balise validée à '
              '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}$gap';
          _lastScanTone = _FeedbackTone.success;
          if (result.checkpointId != null) {
            _session = _session.copyWith(
              status: result.runnerStatus,
              startedAt: _session.startedAt ?? DateTime.now(),
              finishedAt: result.runnerStatus == 'finished' ? (_session.finishedAt ?? DateTime.now()) : null,
              validatedCheckpointIds: {..._session.validatedCheckpointIds, result.checkpointId!}.toList(),
            );
          }
          break;
        case 'out_of_range':
          _lastScanMessage = 'Hors zone (> ${result.toleranceMeters ?? "?"} m)'
              '${result.distanceMeters != null ? " — écart mesuré ${result.distanceMeters!.round()} m" : ""}';
          _lastScanTone = _FeedbackTone.error;
          break;
        case 'out_of_order':
          _lastScanMessage = "Balise hors séquence - respectez l'ordre imposé.";
          _lastScanTone = _FeedbackTone.error;
          break;
      }
    });

    if (_session.status == 'racing') {
      context.read<LocationService>().startTracking();
    } else if (_session.status == 'finished') {
      _onFinished();
    }
  }

  void _onFinished() {
    if (_summaryOpened) return;
    _summaryOpened = true;
    _openSummary();
  }

  Future<void> _openSummary() async {
    // The race is over: no more fixes. The ones still queued are sent before the recap is asked
    // for, so the distance it shows already counts them.
    context.read<LocationService>().stopTracking();
    await _queueProcessor.flush();
    if (!mounted) return;

    final outcome = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RaceSummaryScreen(token: _session.token)),
    );
    if (outcome == raceSummaryQuit) await _quit();
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

  bool get _isImposedOrder => _session.mode == 'imposed_order';

  List<Checkpoint> get _regularCheckpoints {
    final regular = _session.checkpoints.where((c) => c.type == 'checkpoint').toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return regular;
  }

  Checkpoint? get _nextCheckpoint {
    final validated = _session.validatedCheckpointIds.toSet();
    for (final checkpoint in _regularCheckpoints) {
      if (!validated.contains(checkpoint.id)) return checkpoint;
    }

    return _session.checkpoints.where((c) => c.type == 'finish').firstOrNull;
  }

  String _promptLabel() {
    if (_session.status != 'racing') return 'Départ';

    return _isImposedOrder ? (_nextCheckpoint?.name ?? 'la balise') : 'une balise';
  }

  /// What the header counts: the time left when there is an allowance, the elapsed time otherwise.
  /// Running over shows 00:00 rather than a negative.
  Duration get _headlineDuration {
    final limit = _session.timeLimitMinutes;
    if (limit == null) return _elapsed;
    final remaining = Duration(minutes: limit) - _elapsed;

    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final validated = _session.validatedCheckpointIds.toSet();
    final regular = _regularCheckpoints;
    final validatedCount = regular.where((c) => validated.contains(c.id)).length;
    final finished = _session.status == 'finished';

    return Scaffold(
      body: Column(
        children: [
          _header(regular.length, validatedCount),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (finished)
                    _finishedCard()
                  else if (_isImposedOrder)
                    _nextCheckpointCard(_nextCheckpoint)
                  else
                    _freeOrderGrid(regular, validated),
                  if (_lastScanMessage != null) ...[
                    const SizedBox(height: 12),
                    _feedbackBanner(),
                  ],
                  const Spacer(),
                  if (!finished) ...[
                    _scanButton(),
                    const SizedBox(height: 10),
                    _actionRow(),
                  ] else ...[
                    ElevatedButton(
                      onPressed: _openSummary,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: Text('Voir mon récapitulatif', style: EcoFont.sans(size: 15, weight: FontWeight.w600, color: Colors.white)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(onPressed: _quit, child: const Text('Terminer')),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(int totalCheckpoints, int validatedCount) {
    final duration = _headlineDuration;
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final limit = _session.timeLimitMinutes;
    final progress = totalCheckpoints > 0 ? validatedCount / totalCheckpoints : 0.0;

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('e-CO', style: EcoFont.spectral(size: 14, color: Colors.white, height: 1.15)),
                      Text(
                        _session.parcoursName.isEmpty
                            ? _session.courseName
                            : '${_session.parcoursName} · ${_session.modeLabel}',
                        style: EcoFont.sans(size: 10.5, color: EcoColors.onNavyDim, height: 1.15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                EcoStatusPill(label: _online ? 'En ligne' : 'Hors réseau', online: _online),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$minutes:$seconds', style: EcoFont.spectral(size: 32, color: Colors.white)),
                    Text(
                      limit == null ? 'Temps de course' : 'Temps restant / ${limit.toString().padLeft(2, '0')}:00',
                      style: EcoFont.sans(size: 11, color: EcoColors.onNavyDim, letterSpacing: 0.5),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: '$validatedCount',
                        style: EcoFont.spectral(size: 32, color: EcoColors.gold),
                        children: [
                          TextSpan(
                            text: '/$totalCheckpoints',
                            style: EcoFont.spectral(size: 20, color: const Color(0xFF4D7089)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _isImposedOrder ? 'Balises validées' : 'Balises trouvées',
                      style: EcoFont.sans(size: 11, color: EcoColors.onNavyDim, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: EcoColors.navyPill,
                valueColor: const AlwaysStoppedAnimation<Color>(EcoColors.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextCheckpointCard(Checkpoint? checkpoint) {
    if (checkpoint == null) {
      return EcoCard(child: Text('Aucune balise à scanner.', style: EcoFont.sans(size: 13, color: EcoColors.muted)));
    }

    return EcoCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: EcoColors.blueBg, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(checkpoint.shortLabel, style: EcoFont.spectral(size: 20, weight: FontWeight.w700, color: EcoColors.blueDark)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PROCHAINE BALISE',
                  style: EcoFont.sans(size: 11, weight: FontWeight.w600, color: EcoColors.faint, letterSpacing: 0.8),
                ),
                Text(checkpoint.name, style: EcoFont.spectral(size: 18)),
                Text(
                  'Ordre imposé · tolérance ${checkpoint.toleranceMeters} m',
                  style: EcoFont.sans(size: 12.5, color: EcoColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _freeOrderGrid(List<Checkpoint> regular, Set<int> validated) {
    return EcoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "BALISES — DANS L'ORDRE DE VOTRE CHOIX",
            style: EcoFont.sans(size: 11, weight: FontWeight.w600, color: EcoColors.faint, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: regular.map((checkpoint) => _checkpointChip(checkpoint, validated.contains(checkpoint.id))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _checkpointChip(Checkpoint checkpoint, bool done) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? EcoColors.greenBg : Colors.transparent,
        border: Border.all(color: done ? EcoColors.greenBorder : const Color(0xFFB3C6D6), width: done ? 1 : 1.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${checkpoint.position}',
        style: EcoFont.sans(
          size: 14,
          weight: done ? FontWeight.w700 : FontWeight.w600,
          color: done ? EcoColors.greenTx : EcoColors.faint,
        ),
      ),
    );
  }

  Widget _finishedCard() {
    return EcoCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: EcoColors.green, size: 48),
          const SizedBox(height: 10),
          Text('Course terminée', style: EcoFont.spectral(size: 18)),
        ],
      ),
    );
  }

  Widget _feedbackBanner() {
    final (background, border, foreground, icon) = switch (_lastScanTone) {
      _FeedbackTone.success => (EcoColors.greenBg, EcoColors.greenBorder, EcoColors.greenTx, EcoColors.green),
      _FeedbackTone.pending => (EcoColors.goldBg, EcoColors.goldBorder, EcoColors.goldTx, EcoColors.gold),
      _FeedbackTone.error => (EcoColors.redBg, EcoColors.redBorder, EcoColors.red, EcoColors.red),
    };

    return EcoCard(
      background: background,
      borderColor: border,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: icon, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(
              _lastScanTone == _FeedbackTone.error ? Icons.close : Icons.check,
              size: 12,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_lastScanMessage!, style: EcoFont.sans(size: 12.5, weight: FontWeight.w600, color: foreground)),
          ),
        ],
      ),
    );
  }

  Widget _scanButton() {
    return ElevatedButton(
      onPressed: _scan,
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EcoQrGlyph(size: 24, color: Colors.white),
          const SizedBox(width: 12),
          Text(
            _isImposedOrder ? 'Scanner la balise' : 'Scanner une balise',
            style: EcoFont.sans(size: 16, weight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _actionRow() {
    return Row(
      children: [
        // Screen 3f's own rule: no "Carte" button at all when the course is configured with no
        // runner map.
        if (_session.mapVisibility != 'none') ...[
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MapScreen(session: _session, elapsed: _elapsed)),
              ),
              child: const Text('Carte'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: OutlinedButton(
            onPressed: _scanByCode,
            style: OutlinedButton.styleFrom(foregroundColor: EcoColors.muted),
            child: const Text('Code balise'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 76,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: EcoColors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _sos,
            child: Text('SOS', style: EcoFont.sans(size: 13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

enum _FeedbackTone { success, pending, error }

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
