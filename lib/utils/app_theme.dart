import 'package:flutter/material.dart';

/// ChickMark brand colors updated to new Blue palette
///   • Primary blue  (#1750AC)
///   • Secondary blue (#3373C4)
///   • Accent blue    (#5494DA)
class AppTheme {
  // ── Brand palette ──────────────────────────────────────────────────────────
  static const Color primary   = Color(0xFF1750AC); // Blue
  static const Color secondary = Color(0xFF3373C4); // Medium Blue
  static const Color accent    = Color(0xFF5494DA); // Accent Blue

  // Extended Blue Palette
  static const Color blueLightest = Color(0xFF8BD2FA);
  static const Color blueLight    = Color(0xFF73B9EE);
  static const Color blueDarkest  = Color(0xFF003396);

  // ── Status colors ──────────────────────────────────────────────────────────
  static const Color green = Color(0xFF27AE60);
  static const Color amber = Color(0xFFF39C12);
  static const Color red   = Color(0xFFE74C3C);

  // ── Surface / text ─────────────────────────────────────────────────────────
  static const Color background   = Color(0xFFF4F9FF); // cool white
  static const Color cardBg       = Colors.white;
  static const Color textPrimary  = Color(0xFF2B2B2B); // dark charcoal
  static const Color textSecondary = Color(0xFF8E8E8E); // medium gray

  // ── Material theme ─────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: Colors.white,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: accent,
    ),
  );
}

extension ColorFlag on String {
  Color get flagColor {
    switch (this) {
      case 'green': return AppTheme.green;
      case 'amber': return AppTheme.amber;
      case 'red':   return AppTheme.red;
      default:      return AppTheme.textSecondary;
    }
  }

  IconData get flagIcon {
    switch (this) {
      case 'green': return Icons.check_circle;
      case 'amber': return Icons.warning_amber;
      case 'red':   return Icons.cancel;
      default:      return Icons.help_outline;
    }
  }
}
