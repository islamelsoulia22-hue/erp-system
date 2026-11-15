import 'package:flutter/material.dart';

/// Centralized ERP color system. Widgets must use these via Theme,
/// never hard-code color values.
///
/// Theme: ERP Blue (Mobile + Desktop).
abstract final class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primaryLight = Color(0xFFDBEAFE);
  static const Color primaryContainer = Color(0xFFDBEAFE);

  static const Color success = Color(0xFF16A34A);
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerContainer = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0284C7);
  static const Color infoContainer = Color(0xFFE0F2FE);
  static const Color purple = Color(0xFF7C3AED);
  static const Color purpleContainer = Color(0xFFEDE9FE);
  static const Color neutral = Color(0xFF64748B);
  static const Color neutralContainer = Color(0xFFF1F5F9);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF0F172A);
  static const Color secondaryText = Color(0xFF64748B);
  static const Color mutedText = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);

  // Dark mode surfaces — soft charcoal (easy on eyes, no pure black).
  static const Color darkBackground = Color(0xFF1A1E24);
  static const Color darkSurface = Color(0xFF23272F);
  static const Color darkText = Color(0xFFE2E8F0);
  static const Color darkSecondaryText = Color(0xFF9AA3B2);
  static const Color darkDivider = Color(0xFF2E333D);
  static const Color darkPrimary = Color(0xFF93B4FD);
}
