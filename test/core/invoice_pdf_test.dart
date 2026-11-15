import 'package:accounting_system/core/pdf/invoice_pdf.dart';
import 'package:accounting_system/features/purchases/domain/purchases.dart';
import 'package:accounting_system/features/sales/domain/sales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeInvoiceFilename', () {
    test('strips path separators', () {
      expect(sanitizeInvoiceFilename('INV/2026\\001'), 'INV_2026_001.pdf');
      expect(sanitizeInvoiceFilename('PUR:*?"<>|1'), 'PUR_1.pdf');
    });

    test('falls back for blank numbers', () {
      expect(sanitizeInvoiceFilename('   '), 'invoice.pdf');
    });
  });

  group('payment method parsing', () {
    test('sales prefers Arabic payment name', () {
      final inv = SalesInvoice.fromMap({
        'id': 'i1',
        'invoice_number': 'SAL-1',
        'payment_method_id': 'pm1',
        'payment_methods': {
          'code': 'CASH',
          'name': 'Cash',
          'name_ar': 'كاش',
        },
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(inv.paymentMethodId, 'pm1');
      expect(inv.paymentMethodName, 'كاش');
    });

    test('purchases falls back to Latin name', () {
      final inv = PurchaseInvoice.fromMap({
        'id': 'p1',
        'invoice_number': 'PUR-1',
        'grand_total': 100,
        'payment_methods': {'code': 'BANK_TRANSFER', 'name': 'Bank'},
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(inv.paymentMethodName, 'Bank');
    });

    test('purchase totals parse subtotal/discount/tax', () {
      final inv = PurchaseInvoice.fromMap({
        'id': 'p1',
        'invoice_number': 'PUR-1',
        'subtotal': 900,
        'discount': 50,
        'tax_amount': 119,
        'grand_total': 969,
        'warehouses': {'name': 'المخزن الرئيسي'},
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(inv.subtotal, 900);
      expect(inv.discount, 50);
      expect(inv.taxAmount, 119);
      expect(inv.grandTotal, 969);
      expect(inv.warehouseName, 'المخزن الرئيسي');
    });
  });
}
