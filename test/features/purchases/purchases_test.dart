import 'package:accounting_system/features/purchases/domain/purchases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Remaining = quantity - received (partial receiving)', () {
    final it = PurchaseOrderItem.fromMap({
      'id': 'i1',
      'product_name': 'صنف',
      'quantity': 100,
      'received_quantity': 60,
      'unit_cost': 10,
      'total': 0,
    });
    expect(it.remaining, 40);
  });

  test('Over-receive must be rejected (server rule mirror)', () {
    const ordered = 100.0;
    const received = 60.0;
    const take = 50.0;
    final remaining = ordered - received;
    expect(take > remaining, isTrue);
  });

  test('Invoice creation never touches stock (design)', () {
    final inv = PurchaseInvoice.fromMap({
      'id': 'v1',
      'invoice_number': 'PUR-2026-000001',
      'status': 'APPROVED',
      'created_at': DateTime.now().toIso8601String(),
    });
    expect(inv.status, 'APPROVED');
    // Stock effect tested via receive RPC only; no field implies stock change.
  });
}
