// التدفقات المباشرة لنسخة الجهاز (بدون مركز موافقات):
// إنشاء + اعتماد + حركة مخزون في خطوة واحدة — مبيعات/
// مشتريات/مرتجعات. التشغيل:
// flutter test test/local_direct_flows_test.dart
import 'dart:io';

import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_query.dart';
import 'package:accounting_system/core/local/password_hash.dart';
import 'package:accounting_system/features/auth/data/auth_repository.dart';
import 'package:accounting_system/features/customers/data/customers_repository.dart';
import 'package:accounting_system/features/purchases/data/purchases_repository.dart';
import 'package:accounting_system/features/purchases/domain/purchases.dart';
import 'package:accounting_system/features/returns/data/returns_repository.dart';
import 'package:accounting_system/features/sales/data/sales_repository.dart';
import 'package:accounting_system/features/sales/domain/sales.dart';
import 'package:accounting_system/features/shipping/data/shipping_repository.dart';
import 'package:accounting_system/features/suppliers/data/suppliers_repository.dart';
import 'package:accounting_system/features/warehouses/data/warehouses_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openFull() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_direct_test_');
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dir.path, 't.db'),
    options: OpenDatabaseOptions(
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  for (final stmt in LocalDatabase.schemaV1) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV1toV2) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV2toV3) {
    await db.execute(stmt);
  }
  await LocalDatabase.applyV4(db);
  await LocalDatabase.applyV5(db);
  await LocalDatabase.applyV6(db);
  for (final m in const [
    ['CASH', 'Cash', 'كاش'],
    ['CREDIT', 'Credit', 'آجل'],
  ]) {
    await db.rawInsert(
      'INSERT OR IGNORE INTO payment_methods (id, code, name, name_ar, '
      'is_active) VALUES (?, ?, ?, ?, 1)',
      [LocalDatabase.newId(), m[0], m[1], m[2]],
    );
  }
  return db;
}

class _Shop {
  final Database db;
  final LocalDbClient client;
  final String warehouseId;
  final String productId;
  final String customerId;
  final String supplierId;
  final String cashId;
  _Shop(this.db, this.client, this.warehouseId, this.productId,
      this.customerId, this.supplierId, this.cashId);
}

Future<_Shop> _seedShop() async {
  final db = await _openFull();
  LocalSession.clear();
  final salt = PasswordHash.generateSalt();
  final adminId = LocalDatabase.newId();
  await db.insert('users', {
    'id': adminId,
    'full_name': 'مدير',
    'email': 'admin@local',
    'password_salt': salt,
    'password_hash': PasswordHash.hash('admin123', salt),
    'is_active': 1,
    'created_at': DateTime.now().toIso8601String(),
  });
  await LocalDatabase.applyV5(db);
  final client = LocalDbClient(() async => db);
  await AuthRepository(client)
      .signIn(email: 'admin@local', password: 'admin123');

  final wh = WarehousesRepository(client);
  final warehouses = await wh.list();
  final String warehouseId;
  if (warehouses.isEmpty) {
    warehouseId =
        (await wh.create({'name': 'الرئيسي', 'is_active': true})).id;
  } else {
    warehouseId = warehouses.first.id;
  }
  final productId = LocalDatabase.newId();
  await db.insert('products', {
    'id': productId,
    'sku': 'P-1',
    'name': 'صنف اختبار',
    'purchase_price': 40,
    'sale_price': 50,
    'average_cost': 40,
    'minimum_stock': 2,
    'track_inventory': 1,
    'is_active': 1,
    'created_at': DateTime.now().toIso8601String(),
  });
  final cust = await CustomersRepository(client).create({'name': 'عميل 1'});
  final sup = await SuppliersRepository(client).create({'name': 'مورد 1'});
  final cash = await db.query('payment_methods',
      columns: ['id'], where: 'code = ?', whereArgs: ['CASH'], limit: 1);
  return _Shop(db, client, warehouseId, productId, cust.id, sup.id,
      cash.first['id'] as String);
}

Future<void> _closeShop(_Shop s) async {
  LocalSession.clear();
  await s.db.close();
}

void main() {
  test('sales direct: createAndApprove deducts stock immediately', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await wh.adjust(
          warehouseId: s.warehouseId, productId: s.productId, qtyChange: 10);

      final id = await sales.createAndApprove(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 4,
              unitPrice: 50),
        ],
      );
      final inv = await sales.getById(id);
      expect(inv?.status, 'APPROVED');
      expect(inv?.paymentStatus, 'PAID');
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 6);
      expect(stock.first.reserved, 0);
      // حركة SALE مسجلة.
      final moves = await s.db.query('stock_movements',
          where: 'reference_id = ?', whereArgs: [id]);
      expect(moves.any((m) => '${m['movement_type']}' == 'SALE'), isTrue);
      // الخصم المزدوج مرفوض (الحماية من التكرار).
      try {
        await sales.fulfill(id);
        fail('double fulfill must fail');
      } catch (_) {}
    } finally {
      await _closeShop(s);
    }
  });

  test('sales direct SHIPPING: approve reserves, ship deducts', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await wh.adjust(
          warehouseId: s.warehouseId, productId: s.productId, qtyChange: 10);

      final id = await sales.createAndApprove(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        delivery: 'SHIPPING',
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 4,
              unitPrice: 50),
        ],
      );
      expect((await sales.getById(id))?.status, 'APPROVED');
      var stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 10);
      expect(stock.first.reserved, 4);

      final shipId = await ShippingRepository(s.client).create({
        'sales_invoice_id': id,
        'customer_id': s.customerId,
        'recipient_name': 'مستلم',
        'recipient_phone': '01000000000',
        'address': 'عنوان',
        'delivery_method': 'SHIPPING',
        'status': 'PREPARING',
      });
      await ShippingRepository(s.client).ship(shipId);
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 6);
      expect(stock.first.reserved, 0);
    } finally {
      await _closeShop(s);
    }
  });

  test('purchase direct: createAndApprove adds stock', () async {
    final s = await _seedShop();
    try {
      final purchases = PurchasesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      final id = await purchases.createAndApproveInvoice(
        supplierId: s.supplierId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 5,
              unitCost: 40),
        ],
      );
      expect((await purchases.getInvoice(id))?.status, 'APPROVED');
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 5);
    } finally {
      await _closeShop(s);
    }
  });

  test('purchase cash supplier: no supplier record, name snapshot only',
      () async {
    final s = await _seedShop();
    try {
      final purchases = PurchasesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      final id = await purchases.createAndApproveInvoice(
        supplierId: null,
        supplierName: 'مورد نقدي سوق',
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 3,
              unitCost: 40),
        ],
      );
      final inv = await purchases.getInvoice(id);
      expect(inv?.status, 'APPROVED');
      expect(inv?.supplierId, isNull);
      expect(inv?.supplierName, 'مورد نقدي سوق');
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 3);
    } finally {
      await _closeShop(s);
    }
  });

  test('purchase invoice without supplier and without name is rejected',
      () async {
    final s = await _seedShop();
    try {
      final purchases = PurchasesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      final id = await purchases.createInvoice(
        supplierId: null,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 1,
              unitCost: 40),
        ],
      );
      try {
        await purchases.submitInvoice(id);
        fail('submit without supplier/name must fail');
      } catch (_) {}
      expect((await purchases.getInvoice(id))?.status, 'DRAFT');
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.isEmpty ? 0 : stock.first.quantity, 0);
    } finally {
      await _closeShop(s);
    }
  });

  test('returns direct: sales return adds, purchase return deducts', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final purchases = PurchasesRepository(s.client);
      final returns = ReturnsRepository(s.client);
      final wh = WarehousesRepository(s.client);

      // رصيد افتتاحي 10 ثم بيع مباشر 4 → الرصيد 6.
      await wh.adjust(
          warehouseId: s.warehouseId, productId: s.productId, qtyChange: 10);
      final saleId = await sales.createAndApprove(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 4,
              unitPrice: 50),
        ],
      );
      var stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 6);

      final srId = await returns.createAndCompleteSalesReturn(
        invoiceId: saleId,
        warehouseId: s.warehouseId,
        reason: 'تجربة',
        items: [
          {
            'product_id': s.productId,
            'name': 'صنف اختبار',
            'sku': 'P-1',
            'qty': 1,
            'price': 50,
            'tax': 0,
          },
        ],
      );
      expect((await returns.getSales(srId))?.status, 'COMPLETED');
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 7);

      // شراء مباشر 5 → 12، ثم مرتجع مشتريات 2 → 10.
      final buyId = await purchases.createAndApproveInvoice(
        supplierId: s.supplierId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 5,
              unitCost: 40),
        ],
      );
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 12);

      final prId = await returns.createAndCompletePurchaseReturn(
        invoiceId: buyId,
        warehouseId: s.warehouseId,
        reason: 'تجربة',
        items: [
          {
            'product_id': s.productId,
            'name': 'صنف اختبار',
            'sku': 'P-1',
            'qty': 2,
            'price': 40,
            'tax': 0,
            'remaining': 5,
          },
        ],
      );
      expect((await returns.getPurchase(prId))?.status, 'COMPLETED');
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 10);
    } finally {
      await _closeShop(s);
    }
  });
}
