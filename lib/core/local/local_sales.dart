import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_alerts.dart';
import 'local_database.dart';
import 'local_products.dart' show LocalDataFailure;

/// بند فاتورة مبيعات (مدخل من الشاشة).
class LocalSalesLineInput {
  final String? productId;
  final String name;
  final String? sku;
  final double qty;
  final double unitPrice;
  final double discount;
  final double taxRate;
  const LocalSalesLineInput({
    this.productId,
    required this.name,
    this.sku,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.taxRate = 0,
  });
}

class LocalSalesInvoice {
  final String id;
  final String number;
  final String? customerId;
  final String customerName;
  final String? warehouseId;
  final String warehouseName;
  final String? paymentMethodId;
  final String paymentMethodName;
  final String? paymentMethodCode;
  final String status;
  final String paymentStatus;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double grandTotal;
  final String createdAt;
  const LocalSalesInvoice({
    required this.id,
    required this.number,
    this.customerId,
    required this.customerName,
    this.warehouseId,
    required this.warehouseName,
    this.paymentMethodId,
    required this.paymentMethodName,
    this.paymentMethodCode,
    required this.status,
    required this.paymentStatus,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.grandTotal,
    required this.createdAt,
  });

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalSalesInvoice.fromMap(Map<String, Object?> m) {
    return LocalSalesInvoice(
      id: (m['id'] as String?) ?? '',
      number: (m['invoice_number'] as String?) ?? '',
      customerId: m['customer_id'] as String?,
      customerName: (m['customer_name'] as String?) ?? 'عميل نقدي',
      warehouseId: m['warehouse_id'] as String?,
      warehouseName: (m['warehouse_name'] as String?) ?? '—',
      paymentMethodId: m['payment_method_id'] as String?,
      paymentMethodName: (m['method_name'] as String?) ?? '—',
      paymentMethodCode: (m['method_code'] as String?)?.toUpperCase(),
      status: (m['status'] as String?) ?? 'DRAFT',
      paymentStatus: (m['payment_status'] as String?) ?? 'UNPAID',
      subtotal: _n(m['subtotal']),
      discount: _n(m['discount']),
      taxAmount: _n(m['tax_amount']),
      grandTotal: _n(m['grand_total']),
      createdAt: (m['created_at'] as String?) ?? '',
    );
  }
}

class LocalSalesItem {
  final String id;
  final String? productId;
  final String name;
  final double qty;
  final double unitPrice;
  final double unitCost;
  final double discount;
  final double taxRate;
  final double total;
  const LocalSalesItem({
    required this.id,
    this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    required this.total,
  });

  double get net => qty * unitPrice - discount;

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalSalesItem.fromMap(Map<String, Object?> m) {
    return LocalSalesItem(
      id: (m['id'] as String?) ?? '',
      productId: m['product_id'] as String?,
      name: (m['item_name'] as String?) ?? '',
      qty: _n(m['quantity']),
      unitPrice: _n(m['unit_price']),
      unitCost: _n(m['unit_cost']),
      discount: _n(m['discount']),
      taxRate: _n(m['tax_rate']),
      total: _n(m['total']),
    );
  }
}

class LocalSalesReturn {
  final String id;
  final String number;
  final double grandTotal;
  final String createdAt;
  const LocalSalesReturn({
    required this.id,
    required this.number,
    required this.grandTotal,
    required this.createdAt,
  });

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalSalesReturn.fromMap(Map<String, Object?> m) {
    return LocalSalesReturn(
      id: (m['id'] as String?) ?? '',
      number: (m['return_number'] as String?) ?? '',
      grandTotal: _n(m['grand_total']),
      createdAt: (m['created_at'] as String?) ?? '',
    );
  }
}

class LocalSalesRepository {
  final Future<Database> Function() _open;
  LocalSalesRepository(this._open);

  static const int pageSize = 20;

  static const _detailSelect = '''
si.*, c.name AS customer_name, w.name AS warehouse_name,
m.name_ar AS method_name, m.code AS method_code
FROM sales_invoices si
LEFT JOIN customers c ON c.id = si.customer_id
LEFT JOIN warehouses w ON w.id = si.warehouse_id
LEFT JOIN payment_methods m ON m.id = si.payment_method_id
''';

  Future<({List<LocalSalesInvoice> items, int total})> page({
    String query = '',
    String? status,
    int page = 0,
  }) async {
    final db = await _open();
    final q = query.trim();
    final conds = <String>[];
    final args = <Object?>[];
    if (status != null && status.isNotEmpty) {
      conds.add('si.status = ?');
      args.add(status);
    }
    if (q.isNotEmpty) {
      conds.add(
        "(si.invoice_number LIKE ? ESCAPE '\\' OR c.name LIKE ? ESCAPE '\\')",
      );
      final like =
          '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      args.addAll([like, like]);
    }
    final w = conds.isEmpty ? '' : 'WHERE ${conds.join(' AND ')}';
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS c $_detailSelect $w',
      args,
    );
    final total = (totalRows.first['c'] as num?)?.toInt() ?? 0;
    final rows = await db.rawQuery(
      'SELECT $_detailSelect $w ORDER BY si.created_at DESC LIMIT ? OFFSET ?',
      [...args, pageSize, page * pageSize],
    );
    return (
      items: [for (final r in rows) LocalSalesInvoice.fromMap(r)],
      total: total,
    );
  }

  Future<LocalSalesInvoice?> getById(String id) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_detailSelect WHERE si.id = ?', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return LocalSalesInvoice.fromMap(rows.first);
  }

  Future<List<LocalSalesItem>> itemsOf(String invoiceId) async {
    final db = await _open();
    final rows = await db.query(
      'sales_invoice_items',
      where: 'sales_invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'item_name',
    );
    return [for (final r in rows) LocalSalesItem.fromMap(r)];
  }

  Future<List<LocalSalesReturn>> returnsFor(String invoiceId) async {
    final db = await _open();
    final rows = await db.query(
      'sales_returns',
      where: 'sales_invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) LocalSalesReturn.fromMap(r)];
  }

  /// إنشاء فاتورة مسودة (بدون مساس بالمخزون).
  Future<String> create({
    String? customerId,
    required String warehouseId,
    String? paymentMethodId,
    required List<LocalSalesLineInput> lines,
  }) async {
    final clean = lines.where((l) => l.qty > 0).toList();
    if (clean.isEmpty) {
      throw const LocalDataFailure('أضف صنفا واحدا على الأقل.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    var sub = 0.0;
    var tax = 0.0;
    for (final l in clean) {
      final net = l.qty * l.unitPrice - l.discount;
      sub += net;
      tax += net * l.taxRate / 100;
    }
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sales_invoices',
    );
    final seq = ((countRows.first['c'] as num?)?.toInt() ?? 0) + 1;
    final number = 'S-${seq.toString().padLeft(6, '0')}';
    await db.transaction((txn) async {
      await txn.insert('sales_invoices', {
        'id': id,
        'invoice_number': number,
        'customer_id': customerId,
        'warehouse_id': warehouseId,
        'payment_method_id': paymentMethodId,
        'status': 'DRAFT',
        'payment_status': 'UNPAID',
        'subtotal': sub,
        'discount': 0,
        'tax_amount': tax,
        'grand_total': sub + tax,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final l in clean) {
        final net = l.qty * l.unitPrice - l.discount;
        final t = net * l.taxRate / 100;
        await txn.insert('sales_invoice_items', {
          'id': LocalDatabase.newId(),
          'sales_invoice_id': id,
          'product_id': l.productId,
          'item_name': l.name,
          'sku': l.sku,
          'quantity': l.qty,
          'unit_price': l.unitPrice,
          'unit_cost': 0,
          'discount': l.discount,
          'tax_rate': l.taxRate,
          'total': net + t,
        });
      }
    });
    return id;
  }

  /// اعتماد: فحص المتاح + خصم فوري من المخزون (لا حجز
  /// منفصل في نسخة الجهاز) + لقطة تكلفة الشراء الحالية
  /// + تسوية تلقائية لغير الآجل.
  Future<void> approve(String id) async {
    final db = await _open();
    await db.transaction((txn) async {
      final inv = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (inv.isEmpty) {
        throw const LocalDataFailure('الفاتورة غير موجودة.');
      }
      final head = inv.first;
      if (head['status'] != 'DRAFT') {
        throw const LocalDataFailure('الفاتورة ليست مسودة.');
      }
      final warehouseId = head['warehouse_id'] as String?;
      if (warehouseId == null) {
        throw const LocalDataFailure('اختار المخزن أولا.');
      }
      String? methodCode;
      if (head['payment_method_id'] != null) {
        final m = await txn.query(
          'payment_methods',
          columns: ['code'],
          where: 'id = ?',
          whereArgs: [head['payment_method_id']],
          limit: 1,
        );
        if (m.isNotEmpty) {
          methodCode = (m.first['code'] as String?)?.toUpperCase();
        }
      }
      final items = await txn.query(
        'sales_invoice_items',
        where: 'sales_invoice_id = ?',
        whereArgs: [id],
      );
      if (items.isEmpty) {
        throw const LocalDataFailure('لا توجد أصناف في الفاتورة.');
      }
      final total = ((head['grand_total'] as num?)?.toDouble() ?? 0);
      for (final it in items) {
        final pid = it['product_id'] as String?;
        final qty = ((it['quantity'] as num?)?.toDouble() ?? 0);
        final name = (it['item_name'] as String?) ?? 'صنف';
        if (pid != null && qty > 0) {
          final srows = await txn.query(
            'warehouse_stock',
            where: 'warehouse_id = ? AND product_id = ?',
            whereArgs: [warehouseId, pid],
          );
          final onHand = srows.isEmpty
              ? 0.0
              : ((srows.first['quantity'] as num?)?.toDouble() ?? 0);
          final reserved = srows.isEmpty
              ? 0.0
              : ((srows.first['reserved_quantity'] as num?)?.toDouble() ?? 0);
          if (onHand - reserved < qty) {
            throw LocalDataFailure(
              'رصيد $name لا يكفي (المتاح ${(onHand - reserved).toStringAsFixed(2)}).',
            );
          }
          final after = onHand - qty;
          await txn.update(
            'warehouse_stock',
            {'quantity': after},
            where: 'warehouse_id = ? AND product_id = ?',
            whereArgs: [warehouseId, pid],
          );
          await txn.insert('stock_movements', {
            'id': LocalDatabase.newId(),
            'warehouse_id': warehouseId,
            'product_id': pid,
            'movement_type': 'SALE',
            'quantity': qty,
            'before_quantity': onHand,
            'after_quantity': after,
            'reference_type': 'SALES_INVOICE',
            'reference_id': id,
            'notes': 'اعتماد فاتورة مبيعات (لوكال)',
            'created_at': DateTime.now().toIso8601String(),
          });
          // لقطة تكلفة الشراء الحالية للربحية.
          final p = await txn.query(
            'products',
            columns: ['purchase_price'],
            where: 'id = ?',
            whereArgs: [pid],
            limit: 1,
          );
          final cost = p.isEmpty
              ? 0.0
              : ((p.first['purchase_price'] as num?)?.toDouble() ?? 0);
          await txn.update(
            'sales_invoice_items',
            {'unit_cost': cost},
            where: 'id = ?',
            whereArgs: [it['id']],
          );
          await evaluateStockLevels(
            txn,
            warehouseId: warehouseId,
            productId: pid,
          );
        }
      }
      // تسوية تلقائية لغير الآجل.
      var paid = 0.0;
      final prow = await txn.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS s FROM payments WHERE sales_invoice_id = ? AND status = 'COMPLETED'",
        [id],
      );
      paid = ((prow.first['s'] as num?)?.toDouble() ?? 0);
      if (methodCode != null && methodCode != 'CREDIT' && total - paid > 0) {
        await txn.insert('payments', {
          'id': LocalDatabase.newId(),
          'customer_id': head['customer_id'],
          'sales_invoice_id': id,
          'payment_method_id': head['payment_method_id'],
          'amount': total - paid,
          'status': 'COMPLETED',
          'created_at': DateTime.now().toIso8601String(),
        });
        paid = total;
      }
      await txn.update(
        'sales_invoices',
        {
          'status': 'APPROVED',
          'payment_status': paid <= 0
              ? 'UNPAID'
              : paid < total
              ? 'PARTIAL'
              : 'PAID',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// مرتجع مبيعات فوري: يرجع للمخزون بتكلفة اللقطة
  /// الأصلية (أو سعر الشراء الحالي) ولا يتجاوز
  /// كمية الفاتورة ناقص المرتجع السابق.
  Future<String> recordReturn({
    required String invoiceId,
    required List<LocalSalesLineInput> lines,
  }) async {
    final clean = lines.where((l) => l.qty > 0).toList();
    if (clean.isEmpty) {
      throw const LocalDataFailure('ادخل كمية مرتجع أكبر من صفر.');
    }
    final db = await _open();
    final rid = LocalDatabase.newId();
    await db.transaction((txn) async {
      final inv = await txn.query(
        'sales_invoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (inv.isEmpty) {
        throw const LocalDataFailure('الفاتورة غير موجودة.');
      }
      if (inv.first['status'] != 'APPROVED') {
        throw const LocalDataFailure('المرتجع على فاتورة معتمدة فقط.');
      }
      final warehouseId = inv.first['warehouse_id'] as String?;
      if (warehouseId == null) {
        throw const LocalDataFailure('الفاتورة بدون مخزن.');
      }
      final invItems = await txn.query(
        'sales_invoice_items',
        where: 'sales_invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final prevRet = await txn.query(
        'sales_return_items',
        where:
            'sales_return_id IN (SELECT id FROM sales_returns WHERE sales_invoice_id = ?)',
        whereArgs: [invoiceId],
      );
      double qtyOf(
        List<Map<String, Object?>> rows,
        String? pid,
        String name,
        String col,
      ) {
        for (final r in rows) {
          final match = pid != null
              ? r['product_id'] == pid
              : (r['item_name'] as String?) == name;
          if (match) {
            return ((r[col] as num?)?.toDouble() ?? 0);
          }
        }
        return 0;
      }

      double costOf(String? pid, String name) {
        for (final r in invItems) {
          final match = pid != null
              ? r['product_id'] == pid
              : (r['item_name'] as String?) == name;
          if (match) {
            return ((r['unit_cost'] as num?)?.toDouble() ?? 0);
          }
        }
        return 0;
      }

      var sub = 0.0;
      var tax = 0.0;
      final toInsert = <Map<String, Object?>>[];
      for (final l in clean) {
        final allowed =
            qtyOf(invItems, l.productId, l.name, 'quantity') -
            qtyOf(prevRet, l.productId, l.name, 'quantity');
        if (l.qty > allowed) {
          throw LocalDataFailure(
            'كمية المرتجع (${l.name}) تتجاوز المتاح (${allowed.toStringAsFixed(2)}).',
          );
        }
        final net = l.qty * l.unitPrice - l.discount;
        final t = net * l.taxRate / 100;
        sub += net;
        tax += t;
        toInsert.add({
          'id': LocalDatabase.newId(),
          'sales_return_id': rid,
          'product_id': l.productId,
          'item_name': l.name,
          'quantity': l.qty,
          'unit_price': l.unitPrice,
          'unit_cost': costOf(l.productId, l.name),
          'tax_rate': l.taxRate,
          'total': net + t,
        });
      }
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM sales_returns',
      );
      final seq = ((countRows.first['c'] as num?)?.toInt() ?? 0) + 1;
      await txn.insert('sales_returns', {
        'id': rid,
        'return_number': 'SR-${seq.toString().padLeft(6, '0')}',
        'sales_invoice_id': invoiceId,
        'customer_id': inv.first['customer_id'],
        'warehouse_id': warehouseId,
        'status': 'COMPLETED',
        'subtotal': sub,
        'tax_amount': tax,
        'grand_total': sub + tax,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final m in toInsert) {
        await txn.insert('sales_return_items', m);
        final pid = m['product_id'] as String?;
        final qty = (m['quantity'] as num).toDouble();
        if (pid == null) continue;
        final srows = await txn.query(
          'warehouse_stock',
          where: 'warehouse_id = ? AND product_id = ?',
          whereArgs: [warehouseId, pid],
        );
        final before = srows.isEmpty
            ? 0.0
            : ((srows.first['quantity'] as num?)?.toDouble() ?? 0);
        final after = before + qty;
        if (srows.isEmpty) {
          await txn.insert('warehouse_stock', {
            'warehouse_id': warehouseId,
            'product_id': pid,
            'quantity': after,
            'reserved_quantity': 0,
          });
        } else {
          await txn.update(
            'warehouse_stock',
            {'quantity': after},
            where: 'warehouse_id = ? AND product_id = ?',
            whereArgs: [warehouseId, pid],
          );
        }
        await txn.insert('stock_movements', {
          'id': LocalDatabase.newId(),
          'warehouse_id': warehouseId,
          'product_id': pid,
          'movement_type': 'SALES_RETURN',
          'quantity': qty,
          'before_quantity': before,
          'after_quantity': after,
          'reference_type': 'SALES_RETURN',
          'reference_id': rid,
          'created_at': DateTime.now().toIso8601String(),
        });
        await evaluateStockLevels(
          txn,
          warehouseId: warehouseId,
          productId: pid,
        );
      }
    });
    return rid;
  }
}

final localSalesRepositoryProvider = Provider<LocalSalesRepository>((ref) {
  return LocalSalesRepository(() => LocalDatabase.instance.db);
});

final localSalesPageProvider = FutureProvider.autoDispose
    .family<
      ({List<LocalSalesInvoice> items, int total}),
      ({String query, int page})
    >((ref, args) {
      return ref
          .watch(localSalesRepositoryProvider)
          .page(query: args.query, page: args.page);
    });

final localSalesDetailProvider = FutureProvider.autoDispose
    .family<LocalSalesInvoice?, String>((ref, id) {
      return ref.watch(localSalesRepositoryProvider).getById(id);
    });

final localSalesItemsProvider = FutureProvider.autoDispose
    .family<List<LocalSalesItem>, String>((ref, id) {
      return ref.watch(localSalesRepositoryProvider).itemsOf(id);
    });
