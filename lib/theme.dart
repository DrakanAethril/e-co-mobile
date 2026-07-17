import 'package:flutter/material.dart';

// Campus Manager palette (design/design_campus_manager/css/campus-theme.css in the moncampus repo)
// - harmonized colors per design/design_campus_manager/README.md's e-CO section.
class EcoColors {
  static const navy = Color(0xFF12344D);
  static const navyDark = Color(0xFF0B1822);
  static const blue = Color(0xFF1B6BA8);
  static const blueDark = Color(0xFF12507E);
  static const gold = Color(0xFFC9A04E);
  static const green = Color(0xFF2E7D4F);
  static const red = Color(0xFFA43E2E);
  static const bg = Color(0xFFF2F5F8);
  static const border = Color(0xFFDDE5EC);
  static const ink = Color(0xFF1C2B36);
  static const faint = Color(0xFF8A99A6);
}

ThemeData ecoTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: EcoColors.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: EcoColors.blue),
    appBarTheme: const AppBarTheme(
      backgroundColor: EcoColors.navy,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: EcoColors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EcoColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EcoColors.border)),
    ),
  );
}
