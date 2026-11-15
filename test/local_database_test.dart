// أساس النسخة اللوكال: السكيما تتبني بدون أخطاء على
// قاعدة مؤقتة (بدون path_provider).
// التشغيل: flutter test test/local_database_test.dart
import 'dart:io';

import 'package:accounting_system/core/local/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('schema v1 builds all tables', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('sanad_schema_test_');
    final db = await databaseFactoryFfi.openDatabase(p.join(dir.path, 't.db'));
    try {
      for (final stmt in LocalDatabase.schemaV1) {
        await db.execute(stmt);
      }
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = {for (final r in rows) (r['name'] as String)};
      for (final t in [
        'schema_migrations',
        'users',
        'payment_methods',
        'warehouses',
        'products',
        'product_barcodes',
        'customers',
        'suppliers',
        'warehouse_stock',
        'sales_invoices',
        'sales_invoice_items',
        'purchase_invoices',
        'purchase_invoice_items',
        'payments',
        'stock_movements',
        'stock_alerts',
        'shortages',
      ]) {
        expect(names, contains(t), reason: 'missing table $t');
      }
      // إدخال وقراءة سريعة (منتج + مخزون).
      final pid = LocalDatabase.newId();
      final wid = LocalDatabase.newId();
      await db.insert('products', {
        'id': pid,
        'name': 'صنف تجريبي',
        'created_at': '2026-01-01',
      });
      await db.insert('warehouse_stock', {
        'warehouse_id': wid,
        'product_id': pid,
        'quantity': 5,
      });
      final got = await db.rawQuery(
        'SELECT quantity FROM warehouse_stock WHERE product_id = ?',
        [pid],
      );
      expect(got.first['quantity'], 5);
    } finally {
      await db.close();
    }
  });

  test('newId generates unique ids', () {
    final ids = {for (var i = 0; i < 200; i++) LocalDatabase.newId()};
    expect(ids.length, 200);
  });
}
