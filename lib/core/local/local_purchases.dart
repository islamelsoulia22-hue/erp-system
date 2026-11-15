import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_alerts.dart';
import 'local_database.dart';
import 'local_products.dart' show LocalDataFailure;

/// بند فاتورة مشتريات (مدخل من الشاشة).
class LocalPurchaseLineInput {
  final String? productId;
  final String name;
  final String? sku;
  final double qty;
  final double unitCost;
  final double discount;
  final double taxRate;
  const LocalPurchaseLineInput({
    this.productId,
    required this.name,
    this.sku,
    required this.qty,
    required this.unitCost,
    this.discount = 0,
    this.taxRate = 0,
  });
}

class LocalPurchaseInvoice {
  final String id;
  final String number;
  final String? supplierId;
  final String supplierName;
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
  const LocalPurchaseInvoice({
    required this.id,
    required this.number,
    this.supplierId,
    required this.supplierName,
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

  factory LocalPurchaseInvoice.fromMap(Map<String, Object?> m) {
    return LocalPurchaseInvoice(
      id: (m['id'] as String?) ?? '',
      number: (m['invoice_number'] as String?) ?? '',
      supplierId: m['supplier_id'] as String?,
      supplierName: (m['supplier_name'] as String?) ?? 'مورد',
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

class LocalPurchaseItem {
  final String id;
  final String? productId;
  final String name;
  final double qty;
  final double unitCost;
  final double discount;
  final double taxRate;
  final double total;
  const LocalPurchaseItem({
    required this.id,
    this.productId,
    required this.name,
    required this.qty,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    required this.total,
  });

  double get net => qty * unitCost - discount;

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalPurchaseItem.fromMap(Map<String, Object?> m) {
    return LocalPurchaseItem(
      id: (m['id'] as String?) ?? '',
      productId: m['product_id'] as String?,
      name: (m['product_name'] as String?) ?? '',
      qty: _n(m['quantity']),
      unitCost: _n(m['unit_cost']),
      discount: _n(m['discount']),
      taxRate: _n(m['tax_rate']),
      total: _n(m['total']),
    );
  }
}

class LocalPurchaseReturn {
  final String id;
  final String number;
  final double grandTotal;
  final String createdAt;
  const LocalPurchaseReturn({
    required this.id,
    required this.number,
    required this.grandTotal,
    required this.createdAt,
  });

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalPurchaseReturn.fromMap(Map<String, Object?> m) {
    return LocalPurchaseReturn(
      id: (m['id'] as String?) ?? '',
      number: (m['return_number'] as String?) ?? '',
      grandTotal: _n(m['grand_total']),
      createdAt: (m['created_at'] as String?) ?? '',
    );
  }
}

class LocalPurchasesRepository {
  final Future<Database> Function() _open;
  LocalPurchasesRepository(this._open);

  static const int pageSize = 20;

  static const _detailSelect = '''
pi.*, s.name AS supplier_name, w.name AS warehouse_name,
m.name_ar AS method_name, m.code AS method_code
FROM purchase_invoices pi
LEFT JOIN suppliers s ON s.id = pi.supplier_id
LEFT JOIN warehouses w ON w.id = pi.warehouse_id
LEFT JOIN payment_methods m ON m.id = pi.payment_method_id
''';

  Future<({List<LocalPurchaseInvoice> items, int total})> page({
    String query = '',
    String? status,
    int page = 0,
  }) async {
    final db = await _open();
    final q = query.trim();
    final conds = <String>[];
    final args = <Object?>[];
    if (status != null && status.isNotEmpty) {
      conds.add('pi.status = ?');
      args.add(status);
    }
    if (q.isNotEmpty) {
      conds.add(
        "(pi.invoice_number LIKE ? ESCAPE '\\' OR s.name LIKE ? ESCAPE '\\')",
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
      'SELECT $_detailSelect $w ORDER BY pi.created_at DESC LIMIT ? OFFSET ?',
      [...args, pageSize, page * pageSize],
    );
    return (
      items: [for (final r in rows) LocalPurchaseInvoice.fromMap(r)],
      total: total,
    );
  }

  Future<LocalPurchaseInvoice?> getById(String id) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_detailSelect WHERE pi.id = ?', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return LocalPurchaseInvoice.fromMap(rows.first);
  }

  Future<List<LocalPurchaseItem>> itemsOf(String invoiceId) async {
    final db = await _open();
    final rows = await db.query(
      'purchase_invoice_items',
      where: 'purchase_invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'product_name',
    );
    return [for (final r in rows) LocalPurchaseItem.fromMap(r)];
  }

  Future<List<LocalPurchaseReturn>> returnsFor(String invoiceId) async {
    final db = await _open();
    final rows = await db.query(
      'purchase_returns',
      where: 'purchase_invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at DESC',
    );
    return [for (final r in rows) LocalPurchaseReturn.fromMap(r)];
  }

  /// إنشاء فاتورة مسودة + تحديث سعر الشراء في بطاقة
  /// الصنف لآخر سعر مدخل (نفس قاعدة السحابة).
  Future<String> create({
    String? supplierId,
    required String warehouseId,
    String? paymentMethodId,
    required List<LocalPurchaseLineInput> lines,
  }) async {
    if (supplierId == null) {
      throw const LocalDataFailure('اختار المورد أولا.');
    }
    final clean = lines.where((l) => l.qty > 0).toList();
    if (clean.isEmpty) {
      throw const LocalDataFailure('أضف صنفا واحدا على الأقل.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    var sub = 0.0;
    var tax = 0.0;
    for (final l in clean) {
      final net = l.qty * l.unitCost - l.discount;
      sub += net;
      tax += net * l.taxRate / 100;
    }
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM purchase_invoices',
    );
    final seq = ((countRows.first['c'] as num?)?.toInt() ?? 0) + 1;
    final number = 'P-${seq.toString().padLeft(6, '0')}';
    await db.transaction((txn) async {
      await txn.insert('purchase_invoices', {
        'id': id,
        'invoice_number': number,
        'supplier_id': supplierId,
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
        final net = l.qty * l.unitCost - l.discount;
        final t = net * l.taxRate / 100;
        await txn.insert('purchase_invoice_items', {
          'id': LocalDatabase.newId(),
          'purchase_invoice_id': id,
          'product_id': l.productId,
          'product_name': l.name,
          'sku': l.sku,
          'quantity': l.qty,
          'unit_cost': l.unitCost,
          'discount': l.discount,
          'tax_rate': l.taxRate,
          'total': net + t,
        });
        if (l.productId != null) {
          await txn.update(
            'products',
            {'purchase_price': l.unitCost},
            where: 'id = ?',
            whereArgs: [l.productId],
          );
        }
      }
    });
    return id;
  }

  /// اعتماد: ينزل الكمية في مخزن الفاتورة + تسوية
  /// تلقائية لغير الآجل + تحديث حالة السداد.
  Future<void> approve(String id) async {
    final db = await _open();
    await db.transaction((txn) async {
      final inv = await txn.query(
        'purchase_invoices',
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
        'purchase_invoice_items',
        where: 'purchase_invoice_id = ?',
        whereArgs: [id],
      );
      if (items.isEmpty) {
        throw const LocalDataFailure('لا توجد أصناف في الفاتورة.');
      }
      final total = ((head['grand_total'] as num?)?.toDouble() ?? 0);
      // زيادة المخزون.
      for (final it in items) {
        final pid = it['product_id'] as String?;
        final qty = ((it['quantity'] as num?)?.toDouble() ?? 0);
        if (pid == null || qty <= 0) continue;
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
          'movement_type': 'PURCHASE',
          'quantity': qty,
          'before_quantity': before,
          'after_quantity': after,
          'reference_type': 'PURCHASE_INVOICE',
          'reference_id': id,
          'notes': 'اعتماد فاتورة مشتريات (لوكال)',
          'created_at': DateTime.now().toIso8601String(),
        });
        await evaluateStockLevels(
          txn,
          warehouseId: warehouseId,
          productId: pid,
        );
      }
      // تسوية تلقائية لغير الآجل.
      var paid = 0.0;
      final prow = await txn.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS s FROM payments WHERE purchase_invoice_id = ? AND status = 'COMPLETED'",
        [id],
      );
      paid = ((prow.first['s'] as num?)?.toDouble() ?? 0);
      if (methodCode != null && methodCode != 'CREDIT' && total - paid > 0) {
        await txn.insert('payments', {
          'id': LocalDatabase.newId(),
          'supplier_id': head['supplier_id'],
          'purchase_invoice_id': id,
          'payment_method_id': head['payment_method_id'],
          'amount': total - paid,
          'status': 'COMPLETED',
          'created_at': DateTime.now().toIso8601String(),
        });
        paid = total;
      }
      await txn.update(
        'purchase_invoices',
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

  /// مرتجع مشتريات فوري: يخصم من المخزون (لازم رصيد)
  /// ولا يتجاوز كمية الفاتورة ناقص المرتجع السابق.
  Future<String> recordReturn({
    required String invoiceId,
    required List<LocalPurchaseLineInput> lines,
  }) async {
    final clean = lines.where((l) => l.qty > 0).toList();
    if (clean.isEmpty) {
      throw const LocalDataFailure('ادخل كمية مرتجع أكبر من صفر.');
    }
    final db = await _open();
    final rid = LocalDatabase.newId();
    await db.transaction((txn) async {
      final inv = await txn.query(
        'purchase_invoices',
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
        'purchase_invoice_items',
        where: 'purchase_invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final prevRet = await txn.query(
        'purchase_return_items',
        where:
            'purchase_return_id IN (SELECT id FROM purchase_returns WHERE purchase_invoice_id = ?)',
        whereArgs: [invoiceId],
      );
      double returnedOf(String? pid, String name) {
        var s = 0.0;
        for (final r in prevRet) {
          final match = pid != null
              ? r['product_id'] == pid
              : (r['product_name'] as String?) == name;
          if (match) {
            s += ((r['quantity'] as num?)?.toDouble() ?? 0);
          }
        }
        return s;
      }

      double invQtyOf(String? pid, String name) {
        for (final r in invItems) {
          final match = pid != null
              ? r['product_id'] == pid
              : (r['product_name'] as String?) == name;
          if (match) {
            return ((r['quantity'] as num?)?.toDouble() ?? 0);
          }
        }
        return 0;
      }

      var sub = 0.0;
      var tax = 0.0;
      final toInsert = <Map<String, Object?>>[];
      for (final l in clean) {
        final allowed =
            invQtyOf(l.productId, l.name) - returnedOf(l.productId, l.name);
        if (l.qty > allowed) {
          throw LocalDataFailure(
            'كمية المرتجع (${l.name}) تتجاوز المتاح (${allowed.toStringAsFixed(2)}).',
          );
        }
        if (l.productId != null) {
          final srows = await txn.query(
            'warehouse_stock',
            where: 'warehouse_id = ? AND product_id = ?',
            whereArgs: [warehouseId, l.productId],
          );
          final avail = srows.isEmpty
              ? 0.0
              : (((srows.first['quantity'] as num?)?.toDouble() ?? 0) -
                    ((srows.first['reserved_quantity'] as num?)?.toDouble() ??
                        0));
          if (avail < l.qty) {
            throw LocalDataFailure('رصيد ${l.name} لا يكفي للمرتجع.');
          }
        }
        final net = l.qty * l.unitCost - l.discount;
        final t = net * l.taxRate / 100;
        sub += net;
        tax += t;
        toInsert.add({
          'id': LocalDatabase.newId(),
          'purchase_return_id': rid,
          'product_id': l.productId,
          'product_name': l.name,
          'quantity': l.qty,
          'unit_cost': l.unitCost,
          'tax_rate': l.taxRate,
          'total': net + t,
        });
      }
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM purchase_returns',
      );
      final seq = ((countRows.first['c'] as num?)?.toInt() ?? 0) + 1;
      await txn.insert('purchase_returns', {
        'id': rid,
        'return_number': 'PR-${seq.toString().padLeft(6, '0')}',
        'purchase_invoice_id': invoiceId,
        'supplier_id': inv.first['supplier_id'],
        'warehouse_id': warehouseId,
        'status': 'COMPLETED',
        'subtotal': sub,
        'tax_amount': tax,
        'grand_total': sub + tax,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final m in toInsert) {
        await txn.insert('purchase_return_items', m);
        final pid = m['product_id'] as String?;
        final qty = (m['quantity'] as num).toDouble();
        if (pid == null) continue;
        final srows = await txn.query(
          'warehouse_stock',
          where: 'warehouse_id = ? AND product_id = ?',
          whereArgs: [warehouseId, pid],
        );
        final before = ((srows.first['quantity'] as num?)?.toDouble() ?? 0);
        final after = before - qty;
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
          'movement_type': 'PURCHASE_RETURN',
          'quantity': qty,
          'before_quantity': before,
          'after_quantity': after,
          'reference_type': 'PURCHASE_RETURN',
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

final localPurchasesRepositoryProvider = Provider<LocalPurchasesRepository>((
  ref,
) {
  return LocalPurchasesRepository(() => LocalDatabase.instance.db);
});

final localPurchasesPageProvider = FutureProvider.autoDispose
    .family<
      ({List<LocalPurchaseInvoice> items, int total}),
      ({String query, int page})
    >((ref, args) {
      return ref
          .watch(localPurchasesRepositoryProvider)
          .page(query: args.query, page: args.page);
    });

final localPurchaseDetailProvider = FutureProvider.autoDispose
    .family<LocalPurchaseInvoice?, String>((ref, id) {
      return ref.watch(localPurchasesRepositoryProvider).getById(id);
    });

final localPurchaseItemsProvider = FutureProvider.autoDispose
    .family<List<LocalPurchaseItem>, String>((ref, id) {
      return ref.watch(localPurchasesRepositoryProvider).itemsOf(id);
    });
