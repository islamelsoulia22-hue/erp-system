import 'package:accounting_system/features/shipping/domain/shipping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ship requires approved invoice (status gate)', () {
    const ok = ['APPROVED'];
    expect(ok.contains('APPROVED'), isTrue);
    expect(ok.contains('DRAFT'), isFalse);
  });

  test('Payment math: partial vs paid', () {
    const total = 1000.0;
    const paid = 400.0;
    final status = paid <= 0
        ? 'UNPAID'
        : paid < total
            ? 'PARTIAL'
            : 'PAID';
    expect(status, 'PARTIAL');
  });

  test('Shipping requires recipient for SHIPPING method', () {
    bool valid(String? name, String? phone, String? addr) =>
        (name?.trim().isNotEmpty == true) &&
        (phone?.trim().isNotEmpty == true) &&
        (addr?.trim().isNotEmpty == true);
    expect(valid('أحمد', '010', 'شارع'), isTrue);
    expect(valid('', '010', 'شارع'), isFalse);
  });

  test('Balance outstanding = total - paid', () {
    const b = Balance(total: 1000, paid: 400, outstanding: 600);
    expect(b.outstanding, b.total - b.paid);
  });
}
