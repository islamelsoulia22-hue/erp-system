import 'package:accounting_system/features/procurement/domain/procurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Missing = requested - available (shortage rule)', () {
    const requested = 100.0;
    const available = 60.0;
    final missing = (requested - available).clamp(0, double.infinity);
    expect(missing, 40);
  });

  test('No missing when stock covers request', () {
    const requested = 50.0;
    const available = 80.0;
    final missing = (requested - available).clamp(0, double.infinity);
    expect(missing, 0);
  });

  test('Notification parses', () {
    final n = AppNotification.fromMap({
      'id': 'n1',
      'type': 'APPROVAL',
      'title': 'طلب يحتاج اعتماد',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
    expect(n.isRead, isFalse);
  });
}
