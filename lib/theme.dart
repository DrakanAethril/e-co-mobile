import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// The e-CO handoff palette (design/design_handoff_eco in the moncampus repo) - the same tokens as
// Campus Manager's own CSS, so the app and the web read as one product.
class EcoColors {
  static const navy = Color(0xFF12344D);
  static const navyDark = Color(0xFF0B1822);
  static const blue = Color(0xFF1B6BA8);
  static const blueDark = Color(0xFF12507E);
  static const blueBg = Color(0xFFDCEBF7);
  static const blueBgSoft = Color(0xFFEEF5FB);
  static const gold = Color(0xFFC9A04E);
  static const goldStrong = Color(0xFFDBB35F);
  static const goldBg = Color(0xFFFAF1DD);
  static const goldBorder = Color(0xFFECD9AD);
  static const goldTx = Color(0xFF9A7729);
  static const green = Color(0xFF2E7D4F);
  static const greenBg = Color(0xFFE3EDE6);
  static const greenBorder = Color(0xFFCDE3D6);
  static const greenTx = Color(0xFF25543C);
  static const red = Color(0xFFA43E2E);
  static const redBg = Color(0xFFFBECEB);
  static const redBorder = Color(0xFFECC4BD);
  static const bg = Color(0xFFF2F5F8);
  static const border = Color(0xFFDDE5EC);
  static const borderSoft = Color(0xFFEEF2F6);
  static const ink = Color(0xFF1C2B36);
  static const muted = Color(0xFF5B6C79);
  static const faint = Color(0xFF8A99A6);

  // On navy: the secondary text of headers and dark screens.
  static const onNavyDim = Color(0xFF7D99B0);
  static const onNavyMuted = Color(0xFF9FB5C8);
  static const onNavyPositive = Color(0xFF9FD6B4);
  static const navyPill = Color(0xFF1C4562);
  static const dotOnline = Color(0xFF5EC98A);
}

/// The handoff's type system: Spectral 600 for titles and headline figures, Source Sans 3 for
/// everything else. Both families are bundled under assets/google_fonts/.
class EcoFont {
  static TextStyle spectral({
    required double size,
    FontWeight weight = FontWeight.w600,
    Color color = EcoColors.ink,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.spectral(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle sans({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = EcoColors.ink,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.sourceSans3(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Figures: join code, GPS coordinates.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w600,
    Color color = EcoColors.ink,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['RobotoMono', 'Courier'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
}

/// google_fonts would otherwise fetch a family over HTTP the first time it is used, which on a
/// school's filtered network silently degrades every screen to the platform default font.
void disableEcoFontFetching() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

ThemeData ecoTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: EcoColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: EcoColors.blue).copyWith(
      primary: EcoColors.blue,
      secondary: EcoColors.gold,
      surface: Colors.white,
    ),
    textTheme: GoogleFonts.sourceSans3TextTheme(
      ThemeData.light().textTheme.apply(bodyColor: EcoColors.ink, displayColor: EcoColors.ink),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: EcoColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: EcoFont.spectral(size: 15, color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: EcoColors.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: EcoColors.blue,
        disabledForegroundColor: Colors.white70,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: EcoColors.blueDark,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: EcoColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EcoColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EcoColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EcoColors.blue)),
    ),
  );
}

/// The "En ligne / Hors réseau" pill of the runner headers (screens 1b/2b).
class EcoStatusPill extends StatelessWidget {
  final String label;
  final bool online;
  const EcoStatusPill({super.key, required this.label, required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: online ? EcoColors.navyPill : EcoColors.red.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: online ? EcoColors.dotOnline : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: EcoFont.sans(
              size: 10.5,
              weight: FontWeight.w600,
              color: online ? EcoColors.onNavyPositive : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The white, hairline-bordered card of every light screen.
class EcoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final double borderWidth;

  const EcoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? EcoColors.border, width: borderWidth),
      ),
      child: child,
    );
  }
}
