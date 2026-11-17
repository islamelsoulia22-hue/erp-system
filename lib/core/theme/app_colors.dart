import 'package:flutter/material.dart';

/// نظام ألوان YAD (هادئ، واضح، لكل لون وظيفة).
/// الأسماء القديمة محفوظة عشان باقي الشاشات تاخد الشكل الجديد
/// تلقائيا؛ والأسماء الجديدة (midnight, ink, indigo…) من دليل التصميم.
abstract final class AppColors {
  // ── دليل التصميم ───────────────────────────────────────────
  static const Color midnight = Color(0xFF0E1330); // خلفية الهيرو
  static const Color ink = Color(0xFF12163A); // النص وشريط التنقل
  static const Color indigo = Color(0xFF4F46FF); // الإجراء الرئيسي
  static const Color violet = Color(0xFF8B5CF6); // نهاية تدرج الإجراء
  static const Color indigoDeep = Color(0xFF3A33D6); // نص على فاتح
  static const Color mint = Color(0xFF14D0A0); // نجاح وربح
  static const Color sky = Color(0xFF38BDF8); // مشتريات ومعلومات
  static const Color amber = Color(0xFFFFB547); // تنبيه
  static const Color coral = Color(0xFFFF6B7A); // خطر ونقص
  static const Color mist = Color(0xFFF3F5FB); // خلفية الشاشات
  static const Color navy = Color(0xFF2A2F8A); // نهاية تدرج الهيرو
  static const Color navInactive = Color(0xFF8E93C8);
  static const Color heroSoft = Color(0xFFC3C7FF); // نص ثانوي على الهيرو

  static const LinearGradient actionGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [indigo, violet],
  );
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [midnight, Color(0xFF1A1F6B), indigo],
    stops: [0, .55, 1.4],
  );
  static const LinearGradient cardHeroGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [midnight, navy],
  );

  // ── الأسماء القديمة (قيم جديدة) ────────────────────────────
  static const Color primary = indigo;
  static const Color primaryDark = indigoDeep;
  static const Color primaryLight = Color(0xFFECEBFF);
  static const Color primaryContainer = Color(0xFFECEBFF);

  static const Color success = Color(0xFF087A5B);
  static const Color successContainer = Color(0xFFE3F8F1);
  static const Color warning = Color(0xFF8A5A00);
  static const Color warningContainer = Color(0xFFFFF3DC);
  static const Color danger = Color(0xFFC0283E);
  static const Color dangerContainer = Color(0xFFFFE6E9);
  static const Color info = Color(0xFF0B6A99);
  static const Color infoContainer = Color(0xFFE1F4FF);
  static const Color purple = Color(0xFF6D3FD6);
  static const Color purpleContainer = Color(0xFFF0EBFF);
  static const Color neutral = Color(0xFF5D6389);
  static const Color neutralContainer = Color(0xFFECEFF8);

  static const Color background = mist;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = ink;
  static const Color secondaryText = Color(0xFF5D6389);
  static const Color mutedText = navInactive;
  static const Color border = Color(0xFFE6E9F4);
  static const Color divider = Color(0xFFEEF0F8);

  // الدارك مود: ليلي بدرجات الـMidnight.
  static const Color darkBackground = Color(0xFF0B0F28);
  static const Color darkSurface = Color(0xFF151A42);
  static const Color darkText = Color(0xFFE4E6FF);
  static const Color darkSecondaryText = Color(0xFFA9AEDB);
  static const Color darkDivider = Color(0xFF262C68);
  static const Color darkPrimary = Color(0xFF9A94FF);
}
