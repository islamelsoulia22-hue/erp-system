import 'package:flutter/material.dart';

/// Centralized ERP color system. Widgets must use these via Theme,
/// never hard-code color values.
///
/// Theme: ERP Blue (Mobile + Desktop).
abstract final class AppColors {
  static const Color primary = Color(0xFF4F46FF);
  static const Color primaryDark = Color(0xFF3A33D6);
  static const Color primaryLight = Color(0xFFECEBFF);
  static const Color primaryContainer = Color(0xFFECEBFF);

  static const Color success = Color(0xFF14D0A0);
  static const Color successContainer = Color(0xFFE3F8F1);
  static const Color warning = Color(0xFFFFB547);
  static const Color warningContainer = Color(0xFFFFF3DC);
  static const Color danger = Color(0xFFFF6B7A);
  static const Color dangerContainer = Color(0xFFFFE6E9);
  static const Color info = Color(0xFF38BDF8);
  static const Color infoContainer = Color(0xFFE1F4FF);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleContainer = Color(0xFFECEBFF);
  static const Color neutral = Color(0xFF5D6389);
  static const Color neutralContainer = Color(0xFFF3F5FB);

  static const Color background = Color(0xFFF3F5FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF12163A);
  static const Color secondaryText = Color(0xFF5D6389);
  static const Color mutedText = Color(0xFF8E93C8);
  static const Color border = Color(0xFFE6E9F4);
  static const Color divider = Color(0xFFF3F5FB);

  // Dark mode surfaces — soft charcoal (easy on eyes, no pure black).
  static const Color darkBackground = Color(0xFF0E1330);
  static const Color darkSurface = Color(0xFF12163A);
  static const Color darkText = Color(0xFFE6E9F4);
  static const Color darkSecondaryText = Color(0xFFC3C7FF);
  static const Color darkDivider = Color(0xFF2A2F8A);
  static const Color darkPrimary = Color(0xFF8B5CF6);
}
