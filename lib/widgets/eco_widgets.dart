import 'package:flutter/material.dart';

import '../theme.dart';

/// The handoff's QR glyph (three finder squares + the bottom-right module), drawn rather than
/// taken from Material Icons: this exact shape is what sits on the mockups' "Scanner" buttons.
class EcoQrGlyph extends StatelessWidget {
  final double size;
  final Color color;
  const EcoQrGlyph({super.key, this.size = 24, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrGlyphPainter(color)),
    );
  }
}

class _QrGlyphPainter extends CustomPainter {
  final Color color;
  _QrGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the crea's own 24x24 grid, scaled to the widget.
    final scale = size.width / 24;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;

    void finder(double left, double top) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left * scale, top * scale, 7 * scale, 7 * scale),
          Radius.circular(1 * scale),
        ),
        stroke,
      );
    }

    finder(3, 3);
    finder(14, 3);
    finder(3, 14);

    canvas.drawRect(Rect.fromLTWH(14 * scale, 14 * scale, 3 * scale, 3 * scale), stroke);
    canvas.drawLine(Offset(19 * scale, 19 * scale), Offset(21 * scale, 19 * scale), stroke);
    canvas.drawLine(Offset(14 * scale, 19 * scale), Offset(16 * scale, 19 * scale), stroke);
    canvas.drawLine(Offset(19 * scale, 14 * scale), Offset(21 * scale, 14 * scale), stroke);
  }

  @override
  bool shouldRepaint(covariant _QrGlyphPainter oldDelegate) => oldDelegate.color != color;
}

/// The scan screens' viewfinder: four gold brackets and the sweep line, over the camera.
class EcoScanReticle extends StatelessWidget {
  final double size;
  const EcoScanReticle({super.key, this.size = 240});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          _corner(top: 0, left: 0, topSide: true, leftSide: true),
          _corner(top: 0, right: 0, topSide: true, leftSide: false),
          _corner(bottom: 0, left: 0, topSide: false, leftSide: true),
          _corner(bottom: 0, right: 0, topSide: false, leftSide: false),
          Positioned(
            left: 10,
            right: 10,
            top: size * 0.48,
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, EcoColors.gold, Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required bool topSide,
    required bool leftSide,
  }) {
    const side = BorderSide(color: EcoColors.gold, width: 4);
    const radius = Radius.circular(12);

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border(
            top: topSide ? side : BorderSide.none,
            bottom: topSide ? BorderSide.none : side,
            left: leftSide ? side : BorderSide.none,
            right: leftSide ? BorderSide.none : side,
          ),
          borderRadius: BorderRadius.only(
            topLeft: topSide && leftSide ? radius : Radius.zero,
            topRight: topSide && !leftSide ? radius : Radius.zero,
            bottomLeft: !topSide && leftSide ? radius : Radius.zero,
            bottomRight: !topSide && !leftSide ? radius : Radius.zero,
          ),
        ),
      ),
    );
  }
}

/// The navy header of the inner screens: back, Spectral title, subtitle, and a free-form badge on
/// the right (progress, chrono, head count).
class EcoScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBack;

  const EcoScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EcoColors.navy,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBack) ...[
              InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => Navigator.of(context).maybePop(),
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
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: EcoFont.spectral(size: 15, color: Colors.white), overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: EcoFont.sans(size: 11.5, color: EcoColors.onNavyDim),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The shell screens 3d and 4a share: the logotype and its pitch on navy, then a light sheet
/// rounded at the top that carries the form. Only the fields differ between the two.
class EcoAuthShell extends StatelessWidget {
  final String pitch;
  final List<Widget> fields;
  final Widget footer;

  const EcoAuthShell({super.key, required this.pitch, required this.fields, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EcoColors.navy,
      // resizeToAvoidBottomInset keeps the sheet above the keyboard rather than letting the
      // on-screen keyboard overlap the field being typed into.
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).vertical),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset('assets/icons/eco/ic_launcher_96.png', width: 52, height: 52),
                              const SizedBox(width: 12),
                              Text('e-CO', style: EcoFont.spectral(size: 34, color: Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(pitch, style: EcoFont.sans(size: 14, color: EcoColors.onNavyMuted, height: 1.5)),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                    decoration: const BoxDecoration(
                      color: EcoColors.bg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [...fields, const SizedBox(height: 10), footer],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The label sitting above a field on the auth sheets.
class EcoFieldLabel extends StatelessWidget {
  final String text;
  const EcoFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: EcoFont.sans(size: 12.5, weight: FontWeight.w600)),
    );
  }
}

/// The coloured badge sitting on the right of a header: "9/14", "12 en course"...
class EcoHeaderBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const EcoHeaderBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: EcoFont.sans(size: 12, weight: FontWeight.w700, color: foreground)),
    );
  }
}

/// The OpenStreetMap credit that must sit on top of every map.
///
/// This is a licence obligation, not decoration: the tiles come from OpenStreetMap, whose data is
/// published under the ODbL, which requires the credit to be visible wherever the map is shown.
/// Keep it on any new map screen. [trailing] appends a screen-specific detail after a middot (the
/// live-tracking screen uses it for its refresh cadence) without displacing the credit itself.
class EcoMapAttribution extends StatelessWidget {
  final String? trailing;
  final Alignment alignment;

  const EcoMapAttribution({
    super.key,
    this.trailing,
    this.alignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final label = trailing == null
        ? '© OpenStreetMap contributors'
        : '© OpenStreetMap contributors · $trailing';

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            border: Border.all(color: EcoColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: EcoFont.sans(size: 9.5, weight: FontWeight.w600, color: EcoColors.faint),
          ),
        ),
      ),
    );
  }
}
