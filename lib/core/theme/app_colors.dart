import "package:flutter/material.dart";

/// Core palette: primary blue matches the CareShare logo (~Material blue).
/// Names [tealPrimary] / [tealLight] / [tealDark] are kept for a smaller diff; values are brand blue.
abstract final class AppColors {
  static const Color tealPrimary = Color(0xFF2196F3);
  static const Color tealLight = Color(0xFFE3F2FD);
  static const Color tealDark = Color(0xFF1976D2);
  static const Color grey50 = Color(0xFFF9FAFB);
  static const Color grey200 = Color(0xFFE5E7EB);
  static const Color grey500 = Color(0xFF6B7280);
  static const Color grey900 = Color(0xFF111827);
  static const Color amber = Color(0xFFD97706);
  static const Color amberLight = Color(0xFFFEF3C7);
  static const Color red = Color(0xFFDC2626);
  static const Color redLight = Color(0xFFFEE2E2);
  static const Color green = Color(0xFF16A34A);
  static const Color greenLight = Color(0xFFDCFCE7);

  /// Care group home (warm, inspired by CareShare homepage mockup).
  static const Color homeWarmBackground = Color(0xFFF0EBE3);
  static const Color homeHeaderBrown = Color(0xFF3B2A1A);
  static const Color homeHeaderHint = Color(0xFF8C7260);
  static const Color homeTextPrimary = Color(0xFF2A1E13);
  static const Color homeTextMuted = Color(0xFF7A6A5A);
  static const Color homeTodayStripBg = Color(0xFFFEF3E9);
  static const Color homeTodayStripBorder = Color(0xFFE8C9A8);
  static const Color homeAddCta = Color(0xFF3B2A1A);
  static const Color homeFeedBorder = Color(0x1A3B2A1A);
}
