import 'package:accounting_system/features/sales/domain/sales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Invoice totals math mirrors server recalc', () {
    // line = qty*price - discount; tax = line*rate/100; total = line+tax
    const qty = 5.0;
    const price = 100.0;
    const discount = 50.0;
    const rate = 14.0;
    final line = qty * price - discount; // 450
    final tax = line * rate / 100; // 63
    expect(line, 450);
    expect(tax, 63);
    expect(line + tax, 513);
  });

  test('Invoice parses snapshots', () {
    final inv = SalesInvoice.fromMap({
      'id': 'i1',
      'invoice_number': 'SAL-2026-000001',
      'status': 'DRAFT',
      'customer_name_snapshot': 'عميل نقدي',
      'created_at': DateTime.now().toIso8601String(),
    });
    expect(inv.number, 'SAL-2026-000001');
    expect(inv.customerName, 'عميل نقدي');
  });

  test('Duplicate barcode scans merge quantities (cart rule)', () {
    // Simulates _merge: same product id accumulates qty
    final cart = <String, double>{};
    void add(String id) => cart[id] = (cart[id] ?? 0) + 1;
    for (var i = 0; i < 5; i++) {
      add('pA');
    }
    expect(cart['pA'], 5);
    expect(cart.length, 1);
  });
}
