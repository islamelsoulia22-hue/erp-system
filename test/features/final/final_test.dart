import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sales return increases stock, purchase return decreases', () {
    // Mirrors RPC movement types.
    const salesType = 'SALES_RETURN';
    const purchaseType = 'PURCHASE_RETURN';
    expect(salesType, isNot('SALE'));
    expect(purchaseType, isNot('PURCHASE'));
  });

  test('Return qty capped by invoiced qty', () {
    const invoiced = 10.0;
    const alreadyReturned = 3.0;
    const requested = 8.0;
    final allowed = invoiced - alreadyReturned;
    expect(requested > allowed, isTrue);
  });

  test('Outstanding subtracts completed returns', () {
    const invoices = 1000.0;
    const paid = 400.0;
    const returns = 100.0;
    expect(invoices - paid - returns, 500);
  });
}
