import 'package:accounting_system/features/products/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Product parses joined category/unit/barcode', () {
    final p = Product.fromMap({
      'id': 'p1',
      'sku': 'SKU-1',
      'name': 'منتج',
      'purchase_price': 10,
      'sale_price': 15.5,
      'taxable': true,
      'tax_rate': 14,
      'minimum_stock': 2,
      'track_inventory': true,
      'is_customizable': false,
      'is_active': true,
      'product_categories': {'name': 'General', 'name_ar': 'عام'},
      'units': {'name': 'Piece', 'name_ar': 'قطعة'},
      'product_barcodes': [
        {'barcode': '111', 'is_primary': false},
        {'barcode': '222', 'is_primary': true},
      ],
    });
    expect(p.categoryName, 'عام');
    expect(p.unitName, 'قطعة');
    expect(p.primaryBarcode, '222');
    expect(p.salePrice, 15.5);
  });

  test('Product without barcode keeps null primary', () {
    final p = Product.fromMap({
      'id': 'p2',
      'sku': 'SKU-2',
      'name': 'بدون باركود',
      'product_barcodes': [],
    });
    expect(p.primaryBarcode, isNull);
    expect(p.taxable, isTrue);
  });
}
