import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand ──
  static const Color primary = Color(0xFF1769D8);
  static const Color primaryLight = Color(0xFF079FE0);
  static const Color primaryDark = Color(0xFF193FC2);
  static const Color accent = Color(0xFFE65100);
  static const Color accentBg = Color(0xFFFFF3E0);

  // ── Surface ──
  static const Color background = Color(0xFFF5F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF9FAFB);
  static const Color surfaceRaised = Color(0xFFF7FAFD);

  // ── Text ──
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textBody = Color(0xFF1F2937);

  // ── Border ──
  static const Color borderDefault = Color(0xFFE5E7EB);
  static const Color borderFocused = Color(0xFF1769D8);

  // ── Status ──
  static const Color statusGood = Color(0xFF388E3C);
  static const Color statusGoodBg = Color(0xFFE8F5E9);
  static const Color statusWarning = Color(0xFFE67E22);
  static const Color statusWarningBg = Color(0xFFFFF3E0);
  static const Color statusError = Color(0xFFDC2626);
  static const Color statusErrorBg = Color(0xFFFEF2F2);
  static const Color statusActive = Color(0xFF193FC2);
  static const Color statusActiveBg = Color(0xFFE8F2FF);
  static const Color statusNeutralBg = Color(0xFFF3F4F6);
  static const Color statusNeutralText = Color(0xFF4B5563);

  // ── Shadow ──
  static const Color cardShadow = Color(0x14000000);
  static const Color cardShadowElevated = Color(0x1A000000);

  // ── Semantic Aliases (backward compat) ──
  static const Color completedBg = statusGoodBg;
  static const Color completedText = statusGood;
  static const Color activeBg = statusActiveBg;
  static const Color activeText = statusActive;
  static const Color ageBadgeBg = Color(0xFFEAF4FF);
  static const Color cardBackground = surface;
  static const Color greenTab = statusGood;
  static const Color inactiveTab = Color(0xFF9CA3AF);
  static const Color infoBg = ageBadgeBg;
  static const Color infoText = Color(0xFF1557B0);

  // ── Chart ──
  static const Color chart1 = Color(0xFF1769D8);
  static const Color chart2 = Color(0xFF388E3C);
  static const Color chart3 = Color(0xFFE67E22);
  static const Color chart4 = Color(0xFF7E57C2);
  static const Color chart5 = Color(0xFF00897B);
  static const Color chart6 = Color(0xFFD81B60);
  static const Color chart7 = Color(0xFF5D6D7E);
  static const Color chartGridH = Color(0xFFE2EAF2);
  static const Color chartGridV = Color(0xFFEAF0F6);
  static const Color chartEmptyBorder = Color(0xFFE0E7EF);

  // ── Dividers ──
  static const Color divider = Color(0xFFE5E7EB);

  // ── Brand Gradient ──
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}