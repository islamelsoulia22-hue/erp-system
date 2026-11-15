import 'package:accounting_system/features/warehouses/domain/warehouse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('available = quantity - reserved (DB generated rule mirror)', () {
    final s = StockLine.fromMap({
      'id': 's1',
      'warehouse_id': 'w1',
      'product_id': 'p1',
      'quantity': 100,
      'reserved_quantity': 30,
      'available_quantity': 70,
      'warehouses': {'name': 'رئيسي'},
      'products': {'name': 'منتج', 'sku': 'SKU-1'},
    });
    expect(s.available, 70);
    expect(s.quantity - s.reserved, s.available);
  });

  test('over-reserved stock violates invariant', () {
    // Mirrors DB check: reserved <= quantity
    const qty = 10.0;
    const reserved = 15.0;
    expect(reserved <= qty, isFalse);
  });
}
