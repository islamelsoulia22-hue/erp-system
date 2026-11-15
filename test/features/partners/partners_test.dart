import 'package:accounting_system/features/customers/domain/customer.dart';
import 'package:accounting_system/features/suppliers/domain/supplier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Customer parses with auto code default', () {
    final c = Customer.fromMap({
      'id': 'c1',
      'customer_code': 'CUST-000001',
      'name': 'عميل',
      'phone': '01000000000',
      'credit_limit': 5000,
      'is_active': true,
    });
    expect(c.code, 'CUST-000001');
    expect(c.creditLimit, 5000);
    expect(c.isActive, isTrue);
  });

  test('Address display joins parts', () {
    final a = CustomerAddress.fromMap({
      'id': 'a1',
      'customer_id': 'c1',
      'address_line': 'شارع 1',
      'city': 'القاهرة',
      'governorate': 'القاهرة',
      'is_default': true,
    });
    expect(a.display.contains('القاهرة'), isTrue);
    expect(a.isDefault, isTrue);
  });

  test('Supplier parses', () {
    final s = Supplier.fromMap({
      'id': 's1',
      'supplier_code': 'SUP-000001',
      'name': 'مورد',
      'is_active': true,
    });
    expect(s.code, 'SUP-000001');
  });
}
