import 'package:accounting_system/core/utils/format.dart';
import 'package:accounting_system/core/widgets/status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Status labels resolve to Arabic', () {
    expect(AppStatus.labelOf('PENDING_APPROVAL'), 'بانتظار الاعتماد');
    expect(AppStatus.labelOf('APPROVED'), 'معتمدة');
    expect(AppStatus.labelOf('REJECTED'), 'مرفوضة');
    expect(AppStatus.labelOf('DRAFT'), 'مسودة');
    expect(AppStatus.labelOf('DELIVERED'), 'تم التوصيل');
    expect(AppStatus.labelOf('MANUFACTURING'), 'تصنيع');
  });

  test('StatusBadge tones match workflow', () {
    expect(StatusBadge.fromStatus('PENDING_APPROVAL').tone,
        StatusTone.pending);
    expect(
        StatusBadge.fromStatus('APPROVED').tone, StatusTone.approved);
    expect(
        StatusBadge.fromStatus('REJECTED').tone, StatusTone.rejected);
    expect(StatusBadge.fromStatus('SHIPPED').tone,
        StatusTone.processing);
    expect(StatusBadge.fromStatus('MANUFACTURING').tone,
        StatusTone.accent);
    expect(StatusBadge.fromStatus('DRAFT').tone,
        StatusTone.neutral);
  });

  test('Money formatting is stable', () {
    expect(AppFormat.money(1500), contains('ج.م'));
    expect(AppFormat.money(1500), contains('٥٠٠'));
    expect(AppFormat.moneyCompact(2500000), contains('م'));
    expect(AppFormat.moneyCompact(3000), contains('ألف'));
  });
}
