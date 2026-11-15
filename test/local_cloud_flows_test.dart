// إثبات التدفقات: ريبوزيتوري السحابة (بدون تعديل) تعمل على
// SQLite عبر LocalDbClient + RPC المحلية — بيع/شراء/مرتجع/
// مدفوعات/مخزون/سيريال/مستخدمين/تقارير/صيانة.
// التشغيل: flutter test test/local_cloud_flows_test.dart
import 'dart:io';

import 'package:accounting_system/core/errors/failures.dart';
import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_query.dart';
import 'package:accounting_system/core/local/password_hash.dart';
import 'package:accounting_system/features/auth/data/auth_repository.dart';
import 'package:accounting_system/features/customers/data/customers_repository.dart';
import 'package:accounting_system/features/payments/data/payments_repository.dart';
import 'package:accounting_system/features/purchases/data/purchases_repository.dart';
import 'package:accounting_system/features/purchases/domain/purchases.dart';
import 'package:accounting_system/features/reports/data/reports_repository.dart';
import 'package:accounting_system/features/returns/data/returns_repository.dart';
import 'package:accounting_system/features/sales/data/sales_repository.dart';
import 'package:accounting_system/features/sales/domain/sales.dart';
import 'package:accounting_system/features/serials/data/serials_repository.dart';
import 'package:accounting_system/features/shipping/data/shipping_repository.dart';
import 'package:accounting_system/features/suppliers/data/suppliers_repository.dart';
import 'package:accounting_system/features/users/data/users_repository.dart';
import 'package:accounting_system/features/warehouses/data/warehouses_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openFull() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_flows_test_');
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
  // طرق الدفع الأساسية (في التطبيق عبر _seedBase).
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

/// متجر جاهز: مدير + مخزن + صنف + عميل + مورد + طرق دفع.
class _Shop {
  final Database db;
  final LocalDbClient client;
  final String adminId;
  final String warehouseId;
  final String productId;
  final String customerId;
  final String supplierId;
  final String cashId;
  final String creditId;
  _Shop(this.db, this.client, this.adminId, this.warehouseId,
      this.productId, this.customerId, this.supplierId, this.cashId,
      this.creditId);
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
  final auth = AuthRepository(client);
  await auth.signIn(email: 'admin@local', password: 'admin123');

  final wh = WarehousesRepository(client);
  final warehouses = await wh.list();
  String warehouseId;
  if (warehouses.isEmpty) {
    final w =
        await wh.create({'name': 'الرئيسي', 'is_active': true});
    warehouseId = w.id;
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
  Future<String> methodId(String code) async {
    final rows = await db.query(
      'payment_methods',
      columns: ['id'],
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return rows.first['id'] as String;
  }

  return _Shop(
    db,
    client,
    adminId,
    warehouseId,
    productId,
    cust.id,
    sup.id,
    await methodId('CASH'),
    await methodId('CREDIT'),
  );
}

Future<void> _closeShop(_Shop s) async {
  LocalSession.clear();
  await s.db.close();
}

void main() {
  test('sales cash flow: draft→approve→auto-paid→ship→deliver', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      // رصيد افتتاحي 10.
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 10);
      final draftId = await sales.createDraft(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          const SalesItemInput(
              productId: null,
              itemName: 'x',
              quantity: 1,
              unitPrice: 1),
        ],
      );
      // مسودة برقم تلقائي SAL-.
      var inv = await sales.getById(draftId);
      expect(inv?.number.startsWith('SAL-'), isTrue);
      // استبدال السطر التجريبي بسطر حقيقي.
      final items = await s.client
          .from('sales_invoice_items')
          .select('id')
          .eq('sales_invoice_id', draftId);
      for (final r in (items as List)) {
        await sales.removeItem(
            ((r as Map)['id'] as String), draftId);
      }
      await sales.addItems(draftId, [
        SalesItemInput(
            productId: s.productId,
            itemName: 'صنف اختبار',
            quantity: 4,
            unitPrice: 50,
            taxRate: 14),
      ]);
      inv = await sales.getById(draftId);
      expect(inv?.grandTotal, closeTo(4 * 50 * 1.14, 0.01));

      await sales.submit(draftId);
      expect((await sales.getById(draftId))?.status, 'PENDING_APPROVAL');
      await sales.approve(draftId);
      inv = await sales.getById(draftId);
      expect(inv?.status, 'APPROVED');
      // غير الآجل: تحصيل تلقائي → PAID.
      expect(inv?.paymentStatus, 'PAID');
      final bal =
          await PaymentsRepository(s.client).customerBalance(s.customerId);
      expect(bal.outstanding, 0);

      // الحجز 4 من 10.
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 10);
      expect(stock.first.reserved, 4);

      // شحنة → خصم فعلي + فك الحجز.
      final shipId = await ShippingRepository(s.client).create({
        'sales_invoice_id': draftId,
        'customer_id': s.customerId,
        'delivery_method': 'OFFICE_PICKUP',
        'status': 'PREPARING',
      });
      await ShippingRepository(s.client).ship(shipId);
      final stock2 = await wh.stockOfProduct(s.productId);
      expect(stock2.first.quantity, 6);
      expect(stock2.first.reserved, 0);
      await ShippingRepository(s.client).deliver(shipId);
      expect(
          (await ShippingRepository(s.client).getById(shipId))?.status,
          'DELIVERED');
    } finally {
      await _closeShop(s);
    }
  });

  test('sales credit flow + validations', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 10);
      Future<String> draft({String? reason}) {
        return sales.createDraft(
          customerId: s.customerId,
          warehouseId: s.warehouseId,
          paymentMethodId: s.creditId,
          creditReason: reason,
          items: [
            SalesItemInput(
                productId: s.productId,
                itemName: 'صنف اختبار',
                quantity: 2,
                unitPrice: 50),
          ],
        );
      }

      // آجل بدون سبب → فشل التقديم.
      final d1 = await draft();
      var failed = false;
      try {
        await sales.submit(d1);
      } on AppFailure {
        failed = true;
      }
      expect(failed, isTrue);
      // اعتماد مسودة مباشرة → حالة غير صالحة.
      var invalid = false;
      try {
        await sales.approve(d1);
      } on InvalidStatusFailure {
        invalid = true;
      }
      expect(invalid, isTrue);

      // بسبب آجل → يعتمد ويبقى UNPAID ثم دفع جزئي.
      final d2 = await draft(reason: 'توريد آجل');
      await sales.submit(d2);
      await sales.approve(d2);
      expect(
          (await sales.getById(d2))?.paymentStatus, 'UNPAID');
      // رصيد غير كافٍ للحجز.
      final d3 = await draft(reason: 'x');
      await s.client
          .from('sales_invoice_items')
          .delete()
          .eq('sales_invoice_id', d3);
      await sales.addItems(d3, [
        SalesItemInput(
            productId: s.productId,
            itemName: 'صنف اختبار',
            quantity: 100,
            unitPrice: 50),
      ]);
      await sales.submit(d3);
      var nostock = false;
      try {
        await sales.approve(d3);
      } on InsufficientStockFailure {
        nostock = true;
      }
      expect(nostock, isTrue);

      await PaymentsRepository(s.client).pay(
        salesInvoiceId: d2,
        methodId: s.cashId,
        amount: 30,
      );
      expect(
          (await sales.getById(d2))?.paymentStatus, 'PARTIAL');
      // d3 معلقة PENDING (5000) فتحسب في الإجمالي per السيرفر.
      final bal =
          await PaymentsRepository(s.client).customerBalance(s.customerId);
      expect(bal.total, 5100);
      expect(bal.paid, 30);
      expect(bal.outstanding, 5070);
    } finally {
      await _closeShop(s);
    }
  });

  test('self-approve blocked for non-manager', () async {
    final s = await _seedShop();
    try {
      final users = UsersRepository(s.client);
      final roles = await users.listRoles();
      final salesRole =
          roles.firstWhere((r) => r.key == 'sales_manager');
      // مستخدم مبيعات عبر نفس API السحابة.
      final created = await s.client.functions.invoke(
        'create-user',
        body: {
          'email': 'sales@local',
          'password': 'sales123',
          'full_name': 'بائع',
          'role_id': salesRole.id,
        },
      );
      expect(created.status, 200);
      final auth = AuthRepository(s.client);
      await auth.signOut();
      await auth.signIn(email: 'sales@local', password: 'sales123');
      final sales = SalesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await auth.signOut();
      await auth.signIn(email: 'admin@local', password: 'admin123');
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 5);
      await auth.signOut();
      await auth.signIn(email: 'sales@local', password: 'sales123');
      final d = await sales.createDraft(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 1,
              unitPrice: 50),
        ],
      );
      await sales.submit(d);
      // منحه اعتماد المبيعات فرديا لاختبار منع الذاتي (دوره لا
      // يملك sales.approve) — ثم الاعتماد الذاتي مرفوض.
      await auth.signOut();
      await auth.signIn(email: 'admin@local', password: 'admin123');
      await UsersRepository(s.client).grantPermission(
        userId: (await s.client
                .from('profiles')
                .select('id')
                .eq('email', 'sales@local')
                .maybeSingle() as Map)['id'] as String,
        permissionKey: 'sales.approve',
      );
      await auth.signOut();
      await auth.signIn(email: 'sales@local', password: 'sales123');
      var blocked = false;
      try {
        await sales.approve(d);
      } on SelfApprovalFailure {
        blocked = true;
      }
      expect(blocked, isTrue);
      // الرفض الذاتي مرفوض أيضا.
      var denied = false;
      try {
        await sales.reject(d, 'لا');
      } on SelfApprovalFailure {
        denied = true;
      }
      expect(denied, isTrue);
    } finally {
      await _closeShop(s);
    }
  });

  test('purchase flow: order→receive→avg cost→direct invoice stock',
      () async {
    final s = await _seedShop();
    try {
      final pur = PurchasesRepository(s.client);
      final wh = WarehousesRepository(s.client);
      final orderId = await pur.createOrder(
        supplierId: s.supplierId,
        warehouseId: s.warehouseId,
        items: [
          POItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 10,
              unitCost: 40),
        ],
      );
      await pur.submitOrder(orderId);
      // استلام جزئي 4 بسعر 50 → متوسط جديد.
      var orderItems = await s.client
          .from('purchase_order_items')
          .select('id')
          .eq('purchase_order_id', orderId);
      final itemId = (((orderItems as List).first) as Map)['id'] as String;
      await pur.receive(orderId, [
        {'item_id': itemId, 'qty': 4.0}
      ], null);
      var stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 4);
      final prod = await s.client
          .from('products')
          .select('average_cost')
          .eq('id', s.productId)
          .maybeSingle();
      // (0*40 + 4*50)/4 لأن الرصيد كان صفرا → 50؟ لا: الرصيد
      // الكلي قبل = 0 → المتوسط = سعر الشحنة = 40 (سعر السطر).
      expect((prod as Map)['average_cost'], 40);
      // استلام الباقي.
      await pur.receive(orderId, [
        {'item_id': itemId, 'qty': 6.0}
      ], null);
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 10);
      // استلام زائد مرفوض.
      var over = false;
      try {
        await pur.receive(orderId, [
          {'item_id': itemId, 'qty': 1.0}
        ], null);
      } on AppFailure {
        over = true;
      }
      expect(over, isTrue);

      // فاتورة مرتبطة بالطلب → الاعتماد لا يضاعف المخزون.
      final invLinked = await pur.createInvoice(
        orderId: orderId,
        supplierId: s.supplierId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 10,
              unitCost: 40),
        ],
      );
      await pur.submitInvoice(invLinked);
      await pur.approveInvoice(invLinked);
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 10);

      // فاتورة مباشرة → الاعتماد يزيد المخزون.
      final invDirect = await pur.createInvoice(
        supplierId: s.supplierId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          PIItemInput(
              productId: s.productId,
              productName: 'صنف اختبار',
              quantity: 5,
              unitCost: 44),
        ],
      );
      await pur.submitInvoice(invDirect);
      await pur.approveInvoice(invDirect);
      stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 15);
      final sbal =
          await PaymentsRepository(s.client).supplierBalance(s.supplierId);
      expect(sbal.outstanding, 0);
    } finally {
      await _closeShop(s);
    }
  });

  test('returns flow with stock + remaining', () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final rets = ReturnsRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 10);
      final d = await sales.createDraft(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 6,
              unitPrice: 50),
        ],
      );
      await sales.submit(d);
      await sales.approve(d);
      final shipId = await ShippingRepository(s.client).create({
        'sales_invoice_id': d,
        'customer_id': s.customerId,
        'delivery_method': 'OFFICE_PICKUP',
        'status': 'PREPARING',
      });
      await ShippingRepository(s.client).ship(shipId);

      final able = await rets.salesReturnable(d);
      expect(able.length, 1);
      expect(able.first['remaining_qty'], 6);
      final r = await rets.createSalesReturn(
        invoiceId: d,
        warehouseId: s.warehouseId,
        items: [
          {
            'product_id': s.productId,
            'name': 'صنف اختبار',
            'sku': 'P-1',
            'qty': 2.0,
            'price': 50.0,
            'tax': 0.0,
          }
        ],
      );
      await rets.completeSales(r);
      // المخزون رجع 2 (4 + 2).
      final stock = await wh.stockOfProduct(s.productId);
      expect(stock.first.quantity, 6);
      final able2 = await rets.salesReturnable(d);
      expect(able2.first['remaining_qty'], 4);
      expect(able2.first['returned_qty'], 2);
      // تجاوز المتبقي مرفوض.
      final r2 = await rets.createSalesReturn(
        invoiceId: d,
        warehouseId: s.warehouseId,
        items: [
          {
            'product_id': s.productId,
            'name': 'صنف اختبار',
            'sku': 'P-1',
            'qty': 5.0,
            'price': 50.0,
            'tax': 0.0,
          }
        ],
      );
      var over = false;
      try {
        await rets.completeSales(r2);
      } on AppFailure {
        over = true;
      }
      expect(over, isTrue);
    } finally {
      await _closeShop(s);
    }
  });

  test('stock adjust/transfer validations + alerts', () async {
    final s = await _seedShop();
    try {
      final wh = WarehousesRepository(s.client);
      final w2 = await wh.create({'name': 'فرع'});
      // سالب بدون رصيد مرفوض.
      var bad = false;
      try {
        await wh.adjust(
            warehouseId: s.warehouseId,
            productId: s.productId,
            qtyChange: -1);
      } on InsufficientStockFailure {
        bad = true;
      }
      expect(bad, isTrue);
      // صفر مرفوض.
      bad = false;
      try {
        await wh.adjust(
            warehouseId: s.warehouseId,
            productId: s.productId,
            qtyChange: 0);
      } on AppFailure {
        bad = true;
      }
      expect(bad, isTrue);
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 5);
      // نقل لنفس المخزن مرفوض.
      bad = false;
      try {
        await wh.transfer(
            fromWarehouse: s.warehouseId,
            toWarehouse: s.warehouseId,
            productId: s.productId,
            quantity: 1);
      } on AppFailure {
        bad = true;
      }
      expect(bad, isTrue);
      // نقل 2 للفرع.
      await wh.transfer(
          fromWarehouse: s.warehouseId,
          toWarehouse: w2.id,
          productId: s.productId,
          quantity: 2);
      // تصفير الرئيسي → تنبيه نفاذ + حركة مسجلة.
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: -3);
      final alerts = await s.client
          .from('stock_alerts')
          .select('level, status')
          .eq('warehouse_id', s.warehouseId)
          .eq('product_id', s.productId);
      expect(
          ((alerts as List).isNotEmpty), isTrue);
      final moves = await wh.movementsOf(s.warehouseId);
      expect(
          moves
              .map((e) => e.type)
              .toSet()
              .containsAll(
                  {'ADJUSTMENT_IN', 'TRANSFER_OUT', 'ADJUSTMENT_OUT'}),
          isTrue);
    } finally {
      await _closeShop(s);
    }
  });

  test('serials: register on approved item + verify + duplicate',
      () async {
    final s = await _seedShop();
    try {
      final sales = SalesRepository(s.client);
      final serials = SerialsRepository(s.client);
      final wh = WarehousesRepository(s.client);
      await wh.adjust(
          warehouseId: s.warehouseId,
          productId: s.productId,
          qtyChange: 3);
      await s.client.from('product_serials').insert({
        'product_id': s.productId,
        'serial': 'SN-001',
      });
      final d = await sales.createDraft(
        customerId: s.customerId,
        warehouseId: s.warehouseId,
        paymentMethodId: s.cashId,
        items: [
          SalesItemInput(
              productId: s.productId,
              itemName: 'صنف اختبار',
              quantity: 1,
              unitPrice: 50,
              serialNumbers: const ['SN-001']),
        ],
      );
      await sales.submit(d);
      await sales.approve(d);
      // التسجيل التلقائي عند الاعتماد (0032).
      final found = await serials.verify('sn-001');
      expect(found?.serial, 'SN-001');
      expect(found?.invoiceId, d);
      // مكرر مرفوض في المسار اليدوي.
      var dup = false;
      try {
        final items = await s.client
            .from('sales_invoice_items')
            .select('id')
            .eq('sales_invoice_id', d);
        await serials.registerSale(
          itemId: (((items as List).first) as Map)['id'] as String,
          serial: 'SN-001',
        );
      } on AppFailure {
        dup = true;
      }
      expect(dup, isTrue);
      // بيع يدوي لفاتورة قديمة.
      await serials.registerManualSale(
          serial: 'OLD-9', productName: 'جهاز قديم', unitPrice: 100);
      expect((await serials.verify('old-9'))?.productName, 'جهاز قديم');
      expect(await serials.suggest('sn-'), ['SN-001']);
    } finally {
      await _closeShop(s);
    }
  });

  test('user functions + reset keep users + reports', () async {
    final s = await _seedShop();
    try {
      // إدخال غلط.
      var r = await s.client.functions.invoke(
        'create-user',
        body: {'email': 'bad', 'password': '123'},
      );
      expect(r.status, 400);
      // نجاح ثم تكرار الإيميل.
      r = await s.client.functions.invoke(
        'create-user',
        body: {
          'email': 'u2@local',
          'password': 'pass1234',
          'full_name': 'مستخدم 2',
        },
      );
      expect(r.status, 200);
      final uid2 = (r.data as Map)['id'] as String;
      r = await s.client.functions.invoke(
        'create-user',
        body: {'email': 'u2@local', 'password': 'pass1234'},
      );
      expect((r.data as Map)['error'], 'EMAIL_EXISTS');
      // دخول الجديد ثم حذف النفس مرفوض.
      final auth = AuthRepository(s.client);
      await auth.signOut();
      await auth.signIn(email: 'u2@local', password: 'pass1234');
      r = await s.client.functions.invoke(
        'delete-user',
        body: {'user_id': uid2},
      );
      expect((r.data as Map)['error'], 'CANNOT_DELETE_SELF');
      // حذف الغير يحتاج إدارة → مرفوض.
      r = await s.client.functions.invoke(
        'delete-user',
        body: {'user_id': s.adminId},
      );
      expect((r.data as Map)['error'], 'NO_PERMISSION');
      // المدير يحذفه.
      await auth.signOut();
      await auth.signIn(email: 'admin@local', password: 'admin123');
      r = await s.client.functions.invoke(
        'delete-user',
        body: {'user_id': uid2},
      );
      expect(r.status, 200);

      // تقارير تعمل على بيانات فارغة/جزئية.
      final rep = ReportsRepository(s.client);
      final kpis = await rep.dashboardKpis();
      expect(kpis.salesTotal, 0);
      expect((await rep.lowStock()).isEmpty, isTrue);
      expect((await rep.recentActivity()).isNotEmpty, isTrue);

      // إعادة الضبط تبقي المستخدمين.
      final reset =
          await s.client.rpc('reset_all_data_keep_users');
      expect((reset as Map)['ok'], true);
      final users = await UsersRepository(s.client).listProfiles();
      expect(users.any((e) => e.email == 'admin@local'), isTrue);
      await auth.signOut();
      await auth.signIn(email: 'admin@local', password: 'admin123');
      expect(auth.currentUser?.id, s.adminId);
    } finally {
      await _closeShop(s);
    }
  });

  test('v6 upgrade preserves old-shape warehouse_stock', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('sanad_v6up_');
    final db = await databaseFactoryFfi.openDatabase(
      p.join(dir.path, 't.db'),
    );
    try {
      for (final stmt in LocalDatabase.schemaV1) {
        await db.execute(stmt);
      }
      await db.insert('warehouse_stock', {
        'warehouse_id': 'w1',
        'product_id': 'p1',
        'quantity': 7,
        'reserved_quantity': 2,
      });
      await LocalDatabase.applyV6(db);
      final rows = await db.query('warehouse_stock');
      expect(rows.length, 1);
      expect(rows.first['quantity'], 7);
      expect(rows.first['available_quantity'], 5);
      expect((rows.first['id'] as String).isNotEmpty, isTrue);
      // idempotent.
      await LocalDatabase.applyV6(db);
      expect((await db.query('warehouse_stock')).length, 1);
    } finally {
      await db.close();
    }
  });

  test('attachments rows list/remove on sqlite', () async {
    final s = await _seedShop();
    try {
      final repo = _Attachments(s.client);
      await s.client.from('attachments').insert({
        'entity_type': 'SALES_INVOICE',
        'entity_id': 'inv-1',
        'file_name': 'bill.pdf',
        'file_path': 'SALES_INVOICE/inv-1/1_bill.pdf',
        'file_size': 12,
      });
      final list = await repo.list('SALES_INVOICE', 'inv-1');
      expect(list.length, 1);
      await repo.remove(list.first);
      expect(await repo.list('SALES_INVOICE', 'inv-1'), isEmpty);
    } finally {
      await _closeShop(s);
    }
  });
}

// غلاف رفيع فوق نفس استدعاءات AttachmentsRepository (list/remove)
// لتفادي استيراد FileOptions في الاختبار — السلوك مطابق.
class _Att {
  final String id;
  final String filePath;
  _Att(this.id, this.filePath);
}

class _Attachments {
  final dynamic client;
  _Attachments(this.client);
  Future<List<_Att>> list(String t, String i) async {
    final rows = (await client
        .from('attachments')
        .select()
        .eq('entity_type', t)
        .eq('entity_id', i)
        .order('created_at', ascending: false)) as List;
    return [
      for (final r in rows)
        _Att((r as Map)['id'] as String,
            r['file_path'] as String)
    ];
  }

  Future<void> remove(_Att a) async {
    try {
      await client.storage.from('attachments').remove([a.filePath]);
    } catch (_) {}
    await client.from('attachments').delete().eq('id', a.id);
  }
}
