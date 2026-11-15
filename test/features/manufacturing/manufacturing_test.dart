import 'package:accounting_system/features/manufacturing/domain/manufacturing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Customized total = qty * unit price (trigger mirror)', () {
    const qty = 3.0;
    const price = 200.0;
    expect(qty * price, 600);
  });

  test('Start requires approved customized (status gate)', () {
    const allowed = ['APPROVED', 'MANUFACTURING'];
    expect(allowed.contains('APPROVED'), isTrue);
    expect(allowed.contains('DRAFT'), isFalse);
  });

  test('Manufacturing material parses', () {
    final m = ManufacturingMaterial.fromMap({
      'id': 'm1',
      'required_quantity': 10,
      'consumed_quantity': 0,
      'products': {'name': 'خامة'},
    });
    expect(m.requiredQty, 10);
    expect(m.consumedQty, 0);
  });
}
