import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/offline_queue_db.dart';
import '../theme.dart';
import '../widgets/eco_widgets.dart';

class ScanResult {
  final bool queued; // true = network was down, result unknown yet (queued for later sync)
  final String? result; // 'success' | 'out_of_range' | 'out_of_order' | null (queued)
  final int? checkpointId;
  final double? distanceMeters;
  final int? toleranceMeters;
  final String? runnerStatus;
  ScanResult({required this.queued, this.result, this.checkpointId, this.distanceMeters, this.toleranceMeters, this.runnerStatus});
}

// Handoff screen 3e - the same screen for every checkpoint: the server (App\Service\EcoScanService
// in moncampus) is what resolves the code to a checkpoint and enforces order and tolerance, not
// this screen. Manual entry takes over when the QR is unreadable, journalised identically
// server-side (method: 'manual_code').
class ScanScreen extends StatefulWidget {
  final String token;

  /// What the bottom label names: "Départ", "Balise 4", "une balise".
  final String checkpointLabel;

  /// Opens straight onto short-code entry - the race screen's "Code balise" button.
  final bool openManualEntry;

  const ScanScreen({
    super.key,
    required this.token,
    this.checkpointLabel = 'la balise',
    this.openManualEntry = false,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  double? _accuracyMeters;
  // The QR the server just refused: the camera keeps reading it many times a second, and each
  // reading would be refused again.
  String? _refusedCode;

  @override
  void initState() {
    super.initState();
    _readGpsAccuracy();
    if (widget.openManualEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showManualCodeDialog());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The mockup's "GPS OK · ±4 m" pill: what the fix is worth while aiming, since that is what
  /// will decide whether the scan falls inside the tolerance.
  Future<void> _readGpsAccuracy() async {
    final position = await context.read<LocationService>().currentPosition();
    if (mounted) setState(() => _accuracyMeters = position?.accuracy);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty || code == _refusedCode) return;
    _handled = true;
    await _submit(code, method: 'qr_scan');
  }

  Future<void> _submit(String code, {required String method}) async {
    // Taken before waiting on the GPS: the scan happened when the code was read.
    final scannedAt = DateTime.now().toUtc().toIso8601String();
    final api = context.read<ApiClient>();
    final locationService = context.read<LocationService>();
    final position = await locationService.currentPosition();

    // Without a GPS fix the server can never compute a distance and the scan is guaranteed to
    // come back "hors zone" regardless of where the runner actually stands - fail fast here with
    // something actionable instead of wasting the attempt (and the attempt-count shown on 1i).
    if (position == null) {
      _handled = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position GPS indisponible — patientez puis réessayez.')),
      );
      return;
    }

    try {
      final json = await api.runnerScan(widget.token, code, position.latitude, position.longitude,
          method: method, scannedAt: scannedAt);
      if (!mounted) return;
      Navigator.of(context).pop(ScanResult(
        queued: false,
        result: json['result'] as String,
        checkpointId: json['checkpointId'] as int?,
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
        toleranceMeters: json['toleranceMeters'] as int?,
        runnerStatus: json['runnerStatus'] as String?,
      ));
    } on ApiException catch (e) {
      if (e.isRefusal) {
        // The server answered: queued, this scan would be refused again on every pass - it used
        // to sit at the head of the queue and hold back every scan after it. Said now instead.
        _refused(code, e);
      } else {
        await _queue(code, method, position, scannedAt);
      }
    } catch (_) {
      await _queue(code, method, position, scannedAt);
    }
  }

  // Offline (or the server is briefly unreachable, or erring) - queue it, screen 4c/1b's "hors
  // réseau, synchronisé automatiquement" note. The result stays unknown until the next successful
  // /state refresh in RaceScreen.
  Future<void> _queue(String code, String method, Position position, String scannedAt) async {
    await context.read<OfflineQueueDb>().enqueue('scan', {
      'code': code,
      'method': method,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'scannedAt': scannedAt,
    });
    if (!mounted) return;
    Navigator.of(context).pop(ScanResult(queued: true));
  }

  void _refused(String code, ApiException refusal) {
    _refusedCode = code;
    _handled = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(refusal.error == 'checkpointNotFound'
          ? 'Code balise inconnu — vérifiez-le et réessayez.'
          : 'Scan refusé par le serveur — réessayez.'),
    ));
  }

  Future<void> _showManualCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Code balise', style: EcoFont.spectral(size: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'ex. 7GX4K2A'),
          style: EcoFont.mono(size: 17, color: EcoColors.blueDark, letterSpacing: 2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Valider')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && !_handled) {
      _handled = true;
      await _submit(code, method: 'manual_code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.navyDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // The mockup's radial gradient: the camera stays readable in the centre while the edges
          // darken, so the viewfinder and the labels stand out.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 0.95,
                colors: [Color(0x001C3346), Color(0xCC0B1822)],
              ),
            ),
          ),
          Column(
            children: [
              EcoScreenHeader(
                title: 'Balise ${widget.checkpointLabel}',
                subtitle: 'Le chrono démarre au scan',
                trailing: _gpsPill(),
              ),
              const Expanded(child: Center(child: EcoScanReticle())),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
                child: Column(
                  children: [
                    Text(
                      'Visez le QR code de la balise ${widget.checkpointLabel}',
                      textAlign: TextAlign.center,
                      style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _showManualCodeDialog,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.10),
                          foregroundColor: const Color(0xFFCFDDE9),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'QR illisible ? Saisir le code balise',
                          style: EcoFont.sans(size: 13, weight: FontWeight.w600, color: const Color(0xFFCFDDE9)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gpsPill() {
    final accuracy = _accuracyMeters;
    final ready = accuracy != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: (ready ? const Color(0xFF5EC98A) : EcoColors.gold).withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: ready ? EcoColors.dotOnline : EcoColors.gold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            ready ? 'GPS OK · ±${accuracy.round()} m' : 'GPS…',
            style: EcoFont.sans(
              size: 11,
              weight: FontWeight.w600,
              color: ready ? EcoColors.onNavyPositive : EcoColors.goldStrong,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
