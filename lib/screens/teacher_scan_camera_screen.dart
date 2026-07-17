import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

// Reused for every checkpoint (screen 3e, teacher variant) - just returns the decoded short code,
// TeacherLocateScreen does the actual GPS capture + API call.
class TeacherScanCameraScreen extends StatefulWidget {
  const TeacherScanCameraScreen({super.key});

  @override
  State<TeacherScanCameraScreen> createState() => _TeacherScanCameraScreenState();
}

class _TeacherScanCameraScreenState extends State<TeacherScanCameraScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.navyDark,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Scanner la balise')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(border: Border.all(color: EcoColors.gold, width: 3), borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
