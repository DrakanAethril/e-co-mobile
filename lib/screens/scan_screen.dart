import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/offline_queue_db.dart';
import '../theme.dart';

class ScanResult {
  final bool queued; // true = network was down, result unknown yet (queued for later sync)
  final String? result; // 'success' | 'out_of_range' | 'out_of_order' | null (queued)
  final int? checkpointId;
  final double? distanceMeters;
  final int? toleranceMeters;
  final String? runnerStatus;
  ScanResult({required this.queued, this.result, this.checkpointId, this.distanceMeters, this.toleranceMeters, this.runnerStatus});
}

// Screen 3e - same screen for every checkpoint, the server (App\Service\EcoScanService in
// moncampus) is what resolves the code to a checkpoint and enforces order/tolerance, not this
// screen. Falls back to manual code entry if the QR is unreadable, journalised identically
// server-side (method: 'manual_code').
class ScanScreen extends StatefulWidget {
  final String token;
  const ScanScreen({super.key, required this.token});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    await _submit(code, method: 'qr_scan');
  }

  Future<void> _submit(String code, {required String method}) async {
    final api = context.read<ApiClient>();
    final locationService = context.read<LocationService>();
    final queue = context.read<OfflineQueueDb>();
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
      final json = await api.runnerScan(widget.token, code, position.latitude, position.longitude, method: method);
      if (!mounted) return;
      Navigator.of(context).pop(ScanResult(
        queued: false,
        result: json['result'] as String,
        checkpointId: json['checkpointId'] as int?,
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble(),
        toleranceMeters: json['toleranceMeters'] as int?,
        runnerStatus: json['runnerStatus'] as String?,
      ));
    } catch (_) {
      // Offline (or the server is briefly unreachable) - queue it, screen 4c/1b's "hors réseau,
      // synchronisé automatiquement" note. The result stays unknown until the next successful
      // /state refresh in RaceScreen.
      await queue.enqueue('scan', {
        'code': code,
        'method': method,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
      if (!mounted) return;
      Navigator.of(context).pop(ScanResult(queued: true));
    }
  }

  Future<void> _showManualCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code balise'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'ex. VT-B04'),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Scanner une balise'),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(border: Border.all(color: EcoColors.gold, width: 3), borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 30,
            child: Column(
              children: [
                const Text('Visez le QR code de la balise', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _showManualCodeDialog,
                  style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.1), foregroundColor: Colors.white),
                  child: const Text('QR illisible ? Saisir le code balise'),
                ),
              ],
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
