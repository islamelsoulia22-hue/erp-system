// النسخة اللوكال: دورة مشتريات/مبيعات/مدفوعات كاملة.
// التشغيل: flutter test test/local_trade_test.dart
import 'dart:io';

import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_payments.dart';
import 'package:accounting_system/core/local/local_products.dart';
import 'package:accounting_system/core/local/local_purchases.dart';
import 'package:accounting_system/core/local/local_reports.dart';
import 'package:accounting_system/core/local/local_sales.dart';
import 'package:accounting_system/core/local/local_warehouses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openShop() async {
  sqfliteFfiInit();
  final dir =
      await Directory.systemTemp.createTemp('sanad_trade_');
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dir.path, 't.db'),
  );
  for (final s in LocalDatabase.schemaV1) {
    await db.execute(s);
  }
  for (final s in LocalDatabase.migrationV1toV2) {
    await db.execute(s);
  }
  for (final s in LocalDatabase.migrationV2toV3) {
    await db.execute(s);
  }
  await db.insert('payment_methods', {
    'id': 'm-cash',
    'code': 'CASH',
    'name_ar': 'كاش',
    'is_active': 1,
  });
  await db.insert('payment_methods', {
    'id': 'm-credit',
    'code': 'CREDIT',
    'name_ar': 'آجل',
    'is_active': 1,
  });
  await db.insert('warehouses', {
    'id': 'w1',
    'name': 'مخزن 1',
    'is_active': 1,
    'created_at': '2026-01-01',
  });
  await db.insert('products', {
    'id': 'p1',
    'name': 'سكر',
    'purchase_price': 10,
    'sale_price': 15,
    'is_active': 1,
    'created_at': '2026-01-01',
  });
  await db.insert('suppliers', {
    'id': 's1',
    'name': 'مورد 1',
    'is_active': 1,
    'created_at': '2026-01-01',
  });
  await db.insert('customers', {
    'id': 'c1',
    'name': 'عميل 1',
    'is_active': 1,
    'created_at': '2026-01-01',
  });
  return db;
}

void main() {
  test('purchase cash: stock up + auto-settled', () async {
    final db = await _openShop();
    try {
      final repo = LocalPurchasesRepository(() async => db);
      final id = await repo.create(
        supplierId: 's1',
        warehouseId: 'w1',
        paymentMethodId: 'm-cash',
        lines: const [
          LocalPurchaseLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 10,
            unitCost: 12,
          ),
        ],
      );
      // سعر الشراء اتحدث في البطاقة.
      final prod = await LocalProductsRepository(
        () async => db,
      ).getById('p1');
      expect(prod?.purchasePrice, 12);
      await repo.approve(id);
      final inv = await repo.getById(id);
      expect(inv?.status, 'APPROVED');
      expect(inv?.paymentStatus, 'PAID');
      final stock = await db.query(
        'warehouse_stock',
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: ['w1', 'p1'],
      );
      expect(stock.first['quantity'], 10);
      final movs = await db.query(
        'stock_movements',
        where: "reference_type = 'PURCHASE_INVOICE'",
      );
      expect(movs.length, 1);
      final pay = LocalPaymentsRepository(() async => db);
      expect(
        await pay.invoiceOutstanding(purchaseInvoiceId: id),
        0,
      );
    } finally {
      await db.close();
    }
  });

  test('purchase credit: dues then partial payment', () async {
    final db = await _openShop();
    try {
      final repo = LocalPurchasesRepository(() async => db);
      final id = await repo.create(
        supplierId: 's1',
        warehouseId: 'w1',
        paymentMethodId: 'm-credit',
        lines: const [
          LocalPurchaseLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 10,
            unitCost: 10,
          ),
        ],
      );
      await repo.approve(id);
      expect(
        (await repo.getById(id))?.paymentStatus,
        'UNPAID',
      );
      final pay = LocalPaymentsRepository(() async => db);
      expect(
        await pay.invoiceOutstanding(purchaseInvoiceId: id),
        100,
      );
      await pay.record(
        purchaseInvoiceId: id,
        methodId: 'm-cash',
        amount: 40,
      );
      expect(
        (await repo.getById(id))?.paymentStatus,
        'PARTIAL',
      );
      expect(
        await pay.invoiceOutstanding(purchaseInvoiceId: id),
        60,
      );
      expect(
        await pay.partnerOutstanding(supplierId: 's1'),
        60,
      );
    } finally {
      await db.close();
    }
  });

  test('shortage auto-resolves when stock arrives',
      () async {
    final db = await _openShop();
    try {
      await db.insert('shortages', {
        'id': 'sh1',
        'product_id': 'p1',
        'warehouse_id': 'w1',
        'required_qty': 5,
        'status': 'PENDING',
        'created_at': '2026-01-01',
      });
      await db.insert('stock_alerts', {
        'id': 'sa1',
        'product_id': 'p1',
        'warehouse_id': 'w1',
        'level': 'OUT_OF_STOCK',
        'status': 'NEW',
        'available_qty': 0,
        'created_at': '2026-01-01',
      });
      final repo = LocalPurchasesRepository(() async => db);
      final id = await repo.create(
        supplierId: 's1',
        warehouseId: 'w1',
        paymentMethodId: 'm-cash',
        lines: const [
          LocalPurchaseLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 10,
            unitCost: 10,
          ),
        ],
      );
      await repo.approve(id);
      final sh = await db.query(
        'shortages',
        where: 'id = ?',
        whereArgs: ['sh1'],
      );
      expect(sh.first['status'], 'DONE');
      final sa = await db.query(
        'stock_alerts',
        where: 'id = ?',
        whereArgs: ['sa1'],
      );
      expect(sa.first['status'], 'RESOLVED');
    } finally {
      await db.close();
    }
  });

  test('sales: oversell blocked, approve deducts, return restores',
      () async {
    final db = await _openShop();
    try {
      final purch = LocalPurchasesRepository(() async => db);
      final pid = await purch.create(
        supplierId: 's1',
        warehouseId: 'w1',
        paymentMethodId: 'm-cash',
        lines: const [
          LocalPurchaseLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 10,
            unitCost: 10,
          ),
        ],
      );
      await purch.approve(pid);
      final sales = LocalSalesRepository(() async => db);
      final bad = await sales.create(
        warehouseId: 'w1',
        paymentMethodId: 'm-cash',
        lines: const [
          LocalSalesLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 999,
            unitPrice: 15,
          ),
        ],
      );
      await expectLater(
        () => sales.approve(bad),
        throwsA(isA<LocalDataFailure>()),
      );
      final good = await sales.create(
        customerId: 'c1',
        warehouseId: 'w1',
        paymentMethodId: 'm-cash',
        lines: const [
          LocalSalesLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 4,
            unitPrice: 15,
          ),
        ],
      );
      await sales.approve(good);
      var stock = await db.query(
        'warehouse_stock',
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: ['w1', 'p1'],
      );
      expect(stock.first['quantity'], 6);
      // لقطة التكلفة للربحية.
      final items = await sales.itemsOf(good);
      expect(items.first.unitCost, 10);
      expect(
        (await sales.getById(good))?.paymentStatus,
        'PAID',
      );
      // مرتجع يرجع المخزون.
      await sales.recordReturn(
        invoiceId: good,
        lines: const [
          LocalSalesLineInput(
            productId: 'p1',
            name: 'سكر',
            qty: 1,
            unitPrice: 15,
          ),
        ],
      );
      stock = await db.query(
        'warehouse_stock',
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: ['w1', 'p1'],
      );
      expect(stock.first['quantity'], 7);
      // مرتجع زيادة مرفوض.
      await expectLater(
        () => sales.recordReturn(
          invoiceId: good,
          lines: const [
            LocalSalesLineInput(
              productId: 'p1',
              name: 'سكر',
              qty: 99,
              unitPrice: 15,
            ),
          ],
        ),
        throwsA(isA<LocalDataFailure>()),
      );
    } finally {
      await db.close();
    }
  });

  test('warehouse adjust guards + kpis sane', () async {
    final db = await _openShop();
    try {
      final wh = LocalWarehousesRepository(() async => db);
      await wh.adjust(
        warehouseId: 'w1',
        productId: 'p1',
        delta: 20,
      );
      await expectLater(
        () => wh.adjust(
          warehouseId: 'w1',
          productId: 'p1',
          delta: -999,
        ),
        throwsA(isA<LocalDataFailure>()),
      );
      final rep = LocalReportsRepository(() async => db);
      final t = await rep.totals();
      // 20 × شراء 10 = 200 قيمة مخزون.
      expect(t.inventoryValue, 200);
      expect(t.salesTotal, 0);
      final d = await rep.daily();
      expect(d.salesDay, 0);
      expect(d.profitDay, 0);
    } finally {
      await db.close();
    }
  });
}
