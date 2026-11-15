import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Badge tone. Pending=orange, approved=green, rejected=red,
/// processing=blue, manufacturing=purple, cancelled=gray.
enum StatusTone { pending, approved, rejected, processing, accent, neutral }

/// Compact status badge used across all modules.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  const StatusBadge({super.key, required this.label, required this.tone});

  /// Resolves any workflow status string to label + tone.
  factory StatusBadge.fromStatus(String status) {
    final s = status.toUpperCase();
    return switch (s) {
      'PENDING_APPROVAL' || 'PENDING' || 'PARTIALLY_RECEIVED' ||
      'PREPARING' || 'UNPAID' =>
        const StatusBadge(label: '', tone: StatusTone.pending),
      'APPROVED' || 'RECEIVED' || 'DELIVERED' || 'COMPLETED' ||
      'READY' || 'PAID' =>
        const StatusBadge(label: '', tone: StatusTone.approved),
      'REJECTED' =>
        const StatusBadge(label: '', tone: StatusTone.rejected),
      'ORDERED' || 'SHIPPED' || 'IN_PROGRESS' || 'PROCESSING' ||
      'PARTIAL' =>
        const StatusBadge(label: '', tone: StatusTone.processing),
      'MANUFACTURING' =>
        const StatusBadge(label: '', tone: StatusTone.accent),
      _ => const StatusBadge(label: '', tone: StatusTone.neutral),
    };
  }

  (Color, Color) _colors(BuildContext context) {
    final dark =
        Theme.of(context).brightness == Brightness.dark;
    // الدارك مود: خلفية غامقة مشبعة + خط فاتح — الأبيض
    // على الخلفية الفاتحة كان مخلي الكلام مختفي.
    if (dark) {
      return switch (tone) {
        StatusTone.pending => (
            const Color(0xFFFCD34D),
            const Color(0xFF4A2E0B)
          ),
        StatusTone.approved => (
            const Color(0xFF86EFAC),
            const Color(0xFF14532D)
          ),
        StatusTone.rejected => (
            const Color(0xFFFCA5A5),
            const Color(0xFF7F1D1D)
          ),
        StatusTone.processing => (
            const Color(0xFF7DD3FC),
            const Color(0xFF0C4A6E)
          ),
        StatusTone.accent => (
            const Color(0xFFC4B5FD),
            const Color(0xFF4C1D95)
          ),
        StatusTone.neutral => (
            const Color(0xFFCBD5E1),
            const Color(0xFF334155)
          ),
      };
    }
    return switch (tone) {
      StatusTone.pending => (
          const Color(0xFFB45309),
          AppColors.warningContainer
        ),
      StatusTone.approved => (
          const Color(0xFF15803D),
          AppColors.successContainer
        ),
      StatusTone.rejected => (
          const Color(0xFFB91C1C),
          AppColors.dangerContainer
        ),
      StatusTone.processing => (
          const Color(0xFF075985),
          AppColors.infoContainer
        ),
      StatusTone.accent => (
          const Color(0xFF6D28D9),
          AppColors.purpleContainer
        ),
      StatusTone.neutral => (
          const Color(0xFF475569),
          AppColors.neutralContainer
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (fg, bg) = _colors(context);
    final text = label.isEmpty ? AppStatus.labelOf('') : label;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Central Arabic labels for every workflow status.
abstract final class AppStatus {
  static const labels = <String, String>{
    'DRAFT': 'مسودة',
    'PENDING': 'بانتظار الاعتماد',
    'PENDING_APPROVAL': 'بانتظار الاعتماد',
    'APPROVED': 'معتمدة',
    'REJECTED': 'مرفوضة',
    'CANCELLED': 'ملغاة',
    'CONFIRMED': 'مؤكدة',
    'PROCESSING': 'قيد التنفيذ',
    'ORDERED': 'مطلوب',
    'PARTIALLY_RECEIVED': 'استلام جزئي',
    'PARTIAL': 'جزئي',
    'RECEIVED': 'مستلمة',
    'PREPARING': 'تجهيز',
    'SHIPPED': 'تم الشحن',
    'DELIVERED': 'تم التوصيل',
    'IN_PROGRESS': 'قيد التنفيذ',
    'COMPLETED': 'مكتملة',
    'MANUFACTURING': 'تصنيع',
    'READY': 'جاهزة',
    'UNPAID': 'غير مدفوعة',
    'PAID': 'مدفوعة',
    'ACTIVE': 'نشط',
    'INACTIVE': 'موقوف',
  };

  static String labelOf(String status) =>
      labels[status.toUpperCase()] ?? status;

  /// Badge with resolved Arabic label in one call.
  static Widget badge(String status) {
    final base = StatusBadge.fromStatus(status);
    return StatusBadge(
        label: labelOf(status), tone: base.tone);
  }
}
