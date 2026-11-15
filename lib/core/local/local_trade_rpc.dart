import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';
import 'local_query.dart';

/// دوال RPC التجارية منقولة من migrations للـ Dart (نسخة الجهاز).
/// نفس الأسماء/الباراميترات/رسائل الخطأ (snake_case) ليعمل
/// كود الريبوزيتوري بدون تعديل — والتعيين العربي عبر
/// mapSupabaseError (فرع StateError).
///
/// النهائية المعتمدة: approve مبيعات 0032 (0028 + سيريال تلقائي)،
/// approve مشتريات 0035، receive طلبات 0020، مرتجعات 0029،
/// مدفوعات/أرصدة 0033، شحن 0009، سيريال 0030+0031، مخزون
/// check_stock_levels النهائية 0035 (0034 + إقفال النواقص).
void ensureLocalTradeRpcRegistered() {
  if (_done) return;
  _done = true;
  _salesRpc();
  _purchaseRpc();
  _returnsRpc();
  _stockRpc();
  _paymentsRpc();
  _shippingRpc();
  _serialsRpc();
  _maintenanceRpc();
}

bool _done = false;

// ── مساعدات ──

String? _uid() => LocalSession.currentUserId;
String _now() => DateTime.now().toIso8601String();
String _today() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

double _n(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

double _round2(double x) => (x * 100).round() / 100;

Future<Map<String, Object?>?> _one(
  Database db,
  String table,
  String id,
) async {
  final rows = await db.query(
    table,
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

Future<bool> _isActiveUser(Database db, String uid) async {
  try {
    final p = await _one(db, 'profiles', uid);
    if (p == null) return true; // legacy/test بلا ملف = نشط.
    final v = p['is_active'];
    return v == 1 || v == true;
  } catch (_) {
    return true;
  }
}

Future<Set<String>> _permsOf(Database db, String uid) async {
  final out = <String>{};
  try {
    final rows = await db.query(
      'user_permissions',
      columns: ['permission_key'],
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    for (final r in rows) {
      final k = r['permission_key'];
      if (k != null) out.add('$k');
    }
  } catch (_) {}
  if (out.isEmpty) {
    // legacy/test بلا أدوار: كل الصلاحيات (توافق مع اختبارات v4).
    try {
      final roles = await db.query(
        'user_roles',
        columns: ['user_id'],
        where: 'user_id = ?',
        whereArgs: [uid],
        limit: 1,
      );
      final grants = await db.query(
        'user_permission_grants',
        columns: ['user_id'],
        where: 'user_id = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (roles.isEmpty && grants.isEmpty) {
        final all = await db.query('permissions', columns: ['key']);
        for (final r in all) {
          final k = r['key'];
          if (k != null) out.add('$k');
        }
      }
    } catch (_) {}
  }
  return out;
}

Future<bool> _isCompanyManager(Database db, String uid) async {
  try {
    final rows = await db.query(
      'user_permissions',
      columns: ['role_key'],
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    if (rows.isNotEmpty) {
      return rows.any((r) => '${r['role_key']}' == 'company_manager');
    }
  } catch (_) {}
  return true; // legacy/test.
}

/// فحص الدخول/النشاط/الصلاحية — يرمي بنفس نصوص السيرفر.
Future<String> _requireAuth(
  Database db, {
  String? one,
  List<String>? anyOf,
}) async {
  final uid = _uid();
  if (uid == null || uid.isEmpty) throw StateError('NOT_AUTHENTICATED');
  if (!await _isActiveUser(db, uid)) throw StateError('INACTIVE_USER');
  final perms = await _permsOf(db, uid);
  if (one != null && !perms.contains(one)) {
    throw StateError('NO_PERMISSION: $one required');
  }
  if (anyOf != null && !anyOf.any(perms.contains)) {
    throw StateError('NO_PERMISSION');
  }
  return uid;
}

Future<void> _audit(
  Database db,
  String? uid,
  String action,
  String entity,
  String entityId, [
  Map<String, dynamic>? oldD,
  Map<String, dynamic>? newD,
]) async {
  try {
    await db.insert('audit_logs', {
      'id': LocalDatabase.newId(),
      'user_id': uid,
      'action': action,
      'entity_type': entity,
      'entity_id': entityId,
      'old_data': oldD == null ? null : jsonEncode(oldD),
      'new_data': newD == null ? null : jsonEncode(newD),
      'created_at': _now(),
    });
  } catch (_) {}
}

/// رقم مستند تالٍ بنفس عدّاد _nextNumber (مفتاح seq المشترك).
Future<String> _docNumber(
  Database db,
  String table,
  String col,
  String prefix,
  int width,
  bool yearly,
) async {
  final key = 'seq_${table}__$col';
  var n = 0;
  try {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isNotEmpty) n = int.tryParse('${rows.first['value']}') ?? 0;
  } catch (_) {}
  if (n <= 0) {
    try {
      final c = await db.rawQuery('SELECT COUNT(*) AS c FROM "$table"');
      final v = c.first['c'];
      n = v is num ? v.toInt() : 0;
    } catch (_) {}
  }
  final y = DateTime.now().year.toString();
  for (var i = 0; i < 500; i++) {
    n++;
    final num = yearly
        ? '$prefix-$y-${n.toString().padLeft(width, '0')}'
        : '$prefix-${n.toString().padLeft(width, '0')}';
    try {
      final ex = await db.query(
        table,
        columns: ['id'],
        where: '"$col" = ?',
        whereArgs: [num],
        limit: 1,
      );
      if (ex.isEmpty) {
        try {
          await db.rawInsert(
            'INSERT OR REPLACE INTO app_settings (key, value, updated_at) '
            'VALUES (?, ?, ?)',
            [key, '$n', _now()],
          );
        } catch (_) {}
        return num;
      }
    } catch (_) {
      return num;
    }
  }
  return '$prefix-$y-${DateTime.now().millisecondsSinceEpoch}';
}

/// صف المخزون (ينشئه صفرا لو غائبا) → (quantity, reserved).
Future<(double, double)> _ensureStock(
  Database db,
  String warehouseId,
  String productId,
) async {
  try {
    await db.rawInsert(
      'INSERT OR IGNORE INTO warehouse_stock '
      '(id, warehouse_id, product_id, quantity, reserved_quantity, '
      'updated_at) VALUES (?, ?, ?, 0, 0, ?)',
      [LocalDatabase.newId(), warehouseId, productId, _now()],
    );
  } catch (_) {}
  final rows = await db.query(
    'warehouse_stock',
    columns: ['quantity', 'reserved_quantity'],
    where: 'warehouse_id = ? AND product_id = ?',
    whereArgs: [warehouseId, productId],
    limit: 1,
  );
  if (rows.isEmpty) return (0.0, 0.0);
  return (_n(rows.first['quantity']), _n(rows.first['reserved_quantity']));
}

/// هل الصنف متتبع مخزنيا (null = نعم مثل coalesce السيرفر).
Future<bool> _tracked(Database db, String? productId) async {
  if (productId == null || productId.isEmpty) return false;
  try {
    final p = await _one(db, 'products', productId);
    if (p == null) return true;
    final v = p['track_inventory'];
    if (v == null) return true;
    return v == 1 || v == true;
  } catch (_) {
    return true;
  }
}

/// check_stock_levels النهائية (0035): إقفال المحلول + تنبيهات
/// حد أدنى/نفاذ + نواقص تلقائية + إقفال المغطاة. بدون إشعارات
/// (جدول notifications خارج نسخة الجهاز).
Future<void> _checkStockLevels(
  Database db,
  String warehouseId,
  String productId,
) async {
  try {
    final s = await db.query(
      'warehouse_stock',
      columns: ['quantity', 'reserved_quantity'],
      where: 'warehouse_id = ? AND product_id = ?',
      whereArgs: [warehouseId, productId],
      limit: 1,
    );
    if (s.isEmpty) return;
    final avail = _n(s.first['quantity']) - _n(s.first['reserved_quantity']);
    final p = await _one(db, 'products', productId);
    if (p == null) return;
    final min = _n(p['minimum_stock']);
    final sup = p['supplier_id'] as String?;
    if (avail > 0) {
      await db.update(
        'stock_alerts',
        {'status': 'RESOLVED'},
        where: 'product_id = ? AND warehouse_id = ? AND level = ? '
            "AND status = 'NEW'",
        whereArgs: [productId, warehouseId, 'OUT_OF_STOCK'],
      );
    }
    if (min <= 0 || avail > min) {
      await db.update(
        'stock_alerts',
        {'status': 'RESOLVED'},
        where: 'product_id = ? AND warehouse_id = ? AND level = ? '
            "AND status = 'NEW'",
        whereArgs: [productId, warehouseId, 'MINIMUM'],
      );
    }
    // النواقص المغطاة تتقفل DONE.
    if (avail > 0) {
      final pend = await db.query(
        'shortages',
        columns: ['id', 'required_qty'],
        where: 'product_id = ? AND warehouse_id = ? AND status IN '
            "('PENDING', 'ORDERED')",
        whereArgs: [productId, warehouseId],
      );
      for (final r in pend) {
        if (_n(r['required_qty']) <= avail) {
          await db.update(
            'shortages',
            {'status': 'DONE'},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      }
    }
    if (avail <= 0) {
      final ex = await db.query(
        'stock_alerts',
        columns: ['id'],
        where: 'product_id = ? AND warehouse_id = ? AND level = ? '
            "AND status = 'NEW'",
        whereArgs: [productId, warehouseId, 'OUT_OF_STOCK'],
        limit: 1,
      );
      if (ex.isEmpty) {
        final aid = LocalDatabase.newId();
        await db.insert('stock_alerts', {
          'id': aid,
          'product_id': productId,
          'warehouse_id': warehouseId,
          'level': 'OUT_OF_STOCK',
          'status': 'NEW',
          'available_qty': avail,
          'created_at': _now(),
        });
        final need = min > 0 ? min : 1.0;
        final sh = await db.query(
          'shortages',
          columns: ['id', 'required_qty'],
          where: 'product_id = ? AND warehouse_id = ? AND status = ?',
          whereArgs: [productId, warehouseId, 'PENDING'],
          limit: 1,
        );
        if (sh.isNotEmpty) {
          await db.update(
            'shortages',
            {
              'required_qty': _n(sh.first['required_qty']) + need,
              'updated_at': _now(),
            },
            where: 'id = ?',
            whereArgs: [sh.first['id']],
          );
        } else {
          await db.insert('shortages', {
            'id': LocalDatabase.newId(),
            'product_id': productId,
            'warehouse_id': warehouseId,
            'supplier_id': sup,
            'required_qty': need,
            'status': 'PENDING',
            'source_type': 'STOCK_ALERT',
            'source_id': aid,
            'created_at': _now(),
          });
        }
      }
      return;
    }
    if (min > 0 && avail <= min) {
      final ex = await db.query(
        'stock_alerts',
        columns: ['id'],
        where: 'product_id = ? AND warehouse_id = ? AND level = ? '
            "AND status = 'NEW'",
        whereArgs: [productId, warehouseId, 'MINIMUM'],
        limit: 1,
      );
      if (ex.isEmpty) {
        await db.insert('stock_alerts', {
          'id': LocalDatabase.newId(),
          'product_id': productId,
          'warehouse_id': warehouseId,
          'level': 'MINIMUM',
          'status': 'NEW',
          'available_qty': avail,
          'created_at': _now(),
        });
      }
    }
  } catch (_) {}
}

/// متوسط التكلفة المرجح عند الاستلام (0020 + إصلاح صفر 0028).
Future<void> _applyPurchaseCost(
  Database db,
  String productId,
  double takeQty,
  double unitCost,
) async {
  try {
    final p = await _one(db, 'products', productId);
    if (p == null) return;
    var totalQty = 0.0;
    try {
      final r = await db.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS q FROM warehouse_stock '
        'WHERE product_id = ?',
        [productId],
      );
      totalQty = _n(r.first['q']);
    } catch (_) {}
    var avg = _n(p['average_cost']);
    if (avg == 0) {
      // nullif(average_cost,0): الصفر = كأن لا متوسط.
      await db.update(
        'products',
        {'average_cost': unitCost, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [productId],
      );
      return;
    }
    if (totalQty <= 0) {
      await db.update(
        'products',
        {'average_cost': unitCost, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [productId],
      );
      return;
    }
    final next = (totalQty * avg + takeQty * unitCost) / (totalQty + takeQty);
    await db.update(
      'products',
      {'average_cost': next, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [productId],
    );
  } catch (_) {}
}

/// تحديث payment_status من المدفوعات المكتملة (مبيعات/مشتريات).
Future<void> _refreshSalesPayStatus(Database db, String invId) async {
  try {
    final inv = await _one(db, 'sales_invoices', invId);
    if (inv == null) return;
    final total = _n(inv['grand_total']);
    var paid = 0.0;
    try {
      final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
        "WHERE sales_invoice_id = ? AND status = 'COMPLETED'",
        [invId],
      );
      paid = _n(r.first['s']);
    } catch (_) {}
    final st = paid <= 0
        ? 'UNPAID'
        : (paid < total ? 'PARTIAL' : 'PAID');
    await db.update(
      'sales_invoices',
      {'payment_status': st, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [invId],
    );
  } catch (_) {}
}

Future<void> _refreshPurchPayStatus(Database db, String invId) async {
  try {
    final inv = await _one(db, 'purchase_invoices', invId);
    if (inv == null) return;
    final total = _n(inv['grand_total']);
    var paid = 0.0;
    try {
      final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
        "WHERE purchase_invoice_id = ? AND status = 'COMPLETED'",
        [invId],
      );
      paid = _n(r.first['s']);
    } catch (_) {}
    final st = paid <= 0
        ? 'UNPAID'
        : (paid < total ? 'PARTIAL' : 'PAID');
    await db.update(
      'purchase_invoices',
      {'payment_status': st, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [invId],
    );
  } catch (_) {}
}

// ── المبيعات ──

Future<void> _recalcSales(Database db, String invId) async {
  final items = await db.query(
    'sales_invoice_items',
    where: 'sales_invoice_id = ?',
    whereArgs: [invId],
  );
  var sub = 0.0, disc = 0.0, tax = 0.0, total = 0.0;
  for (final it in items) {
    final q = _n(it['quantity']);
    final pr = _n(it['unit_price']);
    final d = _n(it['discount']);
    final r = _n(it['tax_rate']);
    var line = q * pr - d;
    if (line < 0) line = 0;
    final t = _round2(line * r / 100);
    sub += q * pr;
    disc += d;
    tax += t;
    total += line + t;
    await db.update(
      'sales_invoice_items',
      {'tax_amount': t, 'total': line + t},
      where: 'id = ?',
      whereArgs: [it['id']],
    );
  }
  final taxable = (sub - disc) < 0 ? 0.0 : (sub - disc);
  await db.update(
    'sales_invoices',
    {
      'subtotal': sub,
      'discount': disc,
      'taxable_amount': taxable,
      'tax_amount': tax,
      'grand_total': total,
      'updated_at': _now(),
    },
    where: 'id = ?',
    whereArgs: [invId],
  );
}

void _salesRpc() {
  LocalRpc.register('recalc_sales_invoice', (db, p) async {
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    await _recalcSales(db, id);
    return null;
  });

  LocalRpc.register('submit_sales_invoice', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'sales_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    final st = '${inv['status']}';
    if (st != 'DRAFT' && st != 'REJECTED') {
      throw StateError('INVALID_STATUS');
    }
    if ((inv['warehouse_id'] as String?)?.isEmpty != false) {
      throw StateError('WAREHOUSE_REQUIRED');
    }
    final items = await db.query(
      'sales_invoice_items',
      columns: ['id'],
      where: 'sales_invoice_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (items.isEmpty) throw StateError('EMPTY_INVOICE');
    final cid = inv['customer_id'] as String?;
    if (cid != null && cid.isNotEmpty) {
      final c = await _one(db, 'customers', cid);
      if (c != null) {
        await db.update(
          'sales_invoices',
          {
            'customer_name_snapshot': c['name'],
            'customer_phone_snapshot': c['phone'],
            'customer_tax_number_snapshot': c['tax_number'],
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else if (((inv['customer_name_snapshot'] as String?) ?? '')
        .isEmpty) {
      throw StateError('CUSTOMER_REQUIRED');
    }
    final mid = inv['payment_method_id'] as String?;
    if (mid != null && mid.isNotEmpty) {
      final m = await _one(db, 'payment_methods', mid);
      if ('${m?['code']}' == 'CREDIT' &&
          ((inv['credit_reason'] as String?) ?? '').trim().isEmpty) {
        throw StateError('CREDIT_REASON_REQUIRED');
      }
    }
    await _recalcSales(db, id);
    await db.update(
      'sales_invoices',
      {
        'status': 'PENDING_APPROVAL',
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'STATUS_CHANGE', 'SALES_INVOICE', id,
        {'from': st}, {'to': 'PENDING_APPROVAL'});
    return null;
  });

  LocalRpc.register('approve_sales_invoice', (db, p) async {
    final uid = await _requireAuth(db, one: 'sales.approve');
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'sales_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'PENDING_APPROVAL') {
      throw StateError('INVALID_STATUS');
    }
    if ('${inv['created_by']}' == uid &&
        !await _isCompanyManager(db, uid)) {
      throw StateError(
        'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة',
      );
    }
    await _recalcSales(db, id);
    // لقطة التكلفة: المتوسط (>0) وإلا سعر الشراء (0028 nullif).
    final items = await db.query(
      'sales_invoice_items',
      where: 'sales_invoice_id = ?',
      whereArgs: [id],
    );
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      final pr = await _one(db, 'products', pid);
      if (pr == null) continue;
      var avg = _n(pr['average_cost']);
      final cost = avg > 0 ? avg : _n(pr['purchase_price']);
      await db.update(
        'sales_invoice_items',
        {'unit_cost': cost},
        where: 'id = ?',
        whereArgs: [it['id']],
      );
    }
    // حجز المخزون (بدون خصم — الخصم عند الشحن).
    final wh = inv['warehouse_id'] as String?;
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      if (!await _tracked(db, pid)) continue;
      final s = await db.query(
        'warehouse_stock',
        columns: ['quantity', 'reserved_quantity'],
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [wh, pid],
        limit: 1,
      );
      final qty = _n(it['quantity']);
      if (s.isEmpty ||
          (_n(s.first['quantity']) - _n(s.first['reserved_quantity']) <
              qty)) {
        throw StateError('INSUFFICIENT_STOCK: ${it['item_name']}');
      }
      await db.rawUpdate(
        'UPDATE warehouse_stock SET reserved_quantity = '
        'reserved_quantity + ? WHERE warehouse_id = ? AND product_id = ?',
        [qty, wh, pid],
      );
    }
    await db.update(
      'sales_invoices',
      {
        'status': 'APPROVED',
        'approved_by': uid,
        'approved_at': _now(),
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // تسوية تلقائية لغير الآجل.
    final head = await _one(db, 'sales_invoices', id);
    final total = _n(head?['grand_total']);
    var method = '';
    final hmid = head?['payment_method_id'] as String?;
    if (hmid != null && hmid.isNotEmpty) {
      final m = await _one(db, 'payment_methods', hmid);
      method = '${m?['code'] ?? ''}';
    }
    if (method.isNotEmpty && method != 'CREDIT') {
      var paid = 0.0;
      try {
        final r = await db.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
          "WHERE sales_invoice_id = ? AND status = 'COMPLETED'",
          [id],
        );
        paid = _n(r.first['s']);
      } catch (_) {}
      if (total - paid > 0) {
        await db.insert('payments', {
          'id': LocalDatabase.newId(),
          'payment_number': await _docNumber(
            db,
            'payments',
            'payment_number',
            'PAY',
            6,
            true,
          ),
          'customer_id': head?['customer_id'],
          'sales_invoice_id': id,
          'payment_method_id': hmid,
          'amount': total - paid,
          'payment_date': _today(),
          'status': 'COMPLETED',
          'notes': 'تحصيل تلقائي - $method',
          'created_by': uid,
          'created_at': _now(),
        });
      }
    }
    await _refreshSalesPayStatus(db, id);
    // تسجيل السيريالات المختارة (0032 — المتكرر يتخطى بصمت).
    await _autoRegisterSerials(db, uid, id);
    await _audit(db, uid, 'APPROVE', 'SALES_INVOICE', id,
        {'from': 'PENDING_APPROVAL'}, {'to': 'APPROVED'});
    return null;
  });

  LocalRpc.register('reject_sales_invoice', (db, p) async {
    final uid = await _requireAuth(db, one: 'sales.approve');
    final id = p['p_invoice'] as String?;
    final reason = ((p['p_reason'] as String?) ?? '').trim();
    if (reason.isEmpty) throw StateError('REASON_REQUIRED');
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'sales_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'PENDING_APPROVAL') {
      throw StateError('INVALID_STATUS');
    }
    if ('${inv['created_by']}' == uid) {
      throw StateError(
        'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة',
      );
    }
    await db.update(
      'sales_invoices',
      {
        'status': 'REJECTED',
        'rejected_by': uid,
        'rejected_at': _now(),
        'rejection_reason': reason,
        'approved_by': null,
        'approved_at': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'REJECT', 'SALES_INVOICE', id,
        {'from': 'PENDING_APPROVAL'}, {'to': 'REJECTED'});
    return null;
  });

  /// خصم مباشر لمخزون فاتورة مبيعات معتمدة (نسخة الجهاز فقط).
  /// للاستلام الفوري (OFFICE_PICKUP): يخصم الكمية والمحجوز معا
  /// (الاعتماد حجز، وهنا التسليم الفوري) + حركة SALE.
  /// الشحن (SHIPPING) له مسار ship_shipment — لا تنادِ هذه عليه
  /// بعد شحنه (ستفشل بـ NOT_RESERVED وتمنع الخصم المزدوج).
  LocalRpc.register('fulfill_sales_invoice', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'sales_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'APPROVED') {
      throw StateError('INVALID_STATUS');
    }
    final wh = inv['warehouse_id'] as String?;
    if (wh == null || wh.isEmpty) {
      throw StateError('WAREHOUSE_REQUIRED');
    }
    final items = await db.query(
      'sales_invoice_items',
      where: 'sales_invoice_id = ?',
      whereArgs: [id],
    );
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      if (!await _tracked(db, pid)) continue;
      final qty = _n(it['quantity']);
      if (qty <= 0) continue;
      final row = await db.query(
        'warehouse_stock',
        columns: ['quantity', 'reserved_quantity'],
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [wh, pid],
        limit: 1,
      );
      if (row.isEmpty) {
        throw StateError('STOCK_NOT_FOUND: ${it['item_name']}');
      }
      final q = _n(row.first['quantity']);
      final r = _n(row.first['reserved_quantity']);
      if (q < qty) throw StateError('INSUFFICIENT_STOCK: ${it['item_name']}');
      if (r < qty) throw StateError('NOT_RESERVED: ${it['item_name']}');
      await db.rawUpdate(
        'UPDATE warehouse_stock SET quantity = quantity - ?, '
        'reserved_quantity = reserved_quantity - ?, updated_at = ? '
        'WHERE warehouse_id = ? AND product_id = ?',
        [qty, qty, _now(), wh, pid],
      );
      await db.insert('stock_movements', {
        'id': LocalDatabase.newId(),
        'warehouse_id': wh,
        'product_id': pid,
        'movement_type': 'SALE',
        'quantity': qty,
        'before_quantity': q,
        'after_quantity': q - qty,
        'reference_type': 'SALES_INVOICE',
        'reference_id': id,
        'created_by': uid,
        'notes': 'استلام فوري (نسخة الجهاز)',
        'created_at': _now(),
      });
      await _checkStockLevels(db, wh, pid);
    }
    await _audit(db, uid, 'FULFILL', 'SALES_INVOICE', id,
        {'from': 'APPROVED'}, {'to': 'APPROVED'});
    return null;
  });
}

/// تسجيل سيريالات الفاتورة تلقائيا عند الاعتماد (0032).
Future<void> _autoRegisterSerials(
  Database db,
  String uid,
  String invId,
) async {
  try {
    final inv = await _one(db, 'sales_invoices', invId);
    final items = await db.query(
      'sales_invoice_items',
      where: 'sales_invoice_id = ?',
      whereArgs: [invId],
    );
    for (final it in items) {
      final raw = it['serial_numbers'];
      if (raw == null) continue;
      List<dynamic> list;
      try {
        final d = raw is String ? jsonDecode(raw) : raw;
        if (d is! List) continue;
        list = d;
      } catch (_) {
        continue;
      }
      for (final e in list) {
        final v = '$e'.trim();
        if (v.isEmpty) continue;
        try {
          final ex = await db.rawQuery(
            'SELECT id FROM serial_sales WHERE lower(serial) = lower(?) '
            'LIMIT 1',
            [v],
          );
          if (ex.isNotEmpty) continue;
        } catch (_) {
          continue;
        }
        final pid = it['product_id'] as String?;
        await db.insert('serial_sales', {
          'id': LocalDatabase.newId(),
          'serial': v,
          'product_id': pid,
          'product_name_snapshot': it['item_name'],
          'customer_id': inv?['customer_id'],
          'customer_name_snapshot': inv?['customer_name_snapshot'],
          'customer_phone_snapshot': inv?['customer_phone_snapshot'],
          'sales_invoice_id': invId,
          'sales_invoice_item_id': it['id'],
          'unit_price': _n(it['unit_price']),
          'unit_cost': _n(it['unit_cost']),
          'sold_at': _now(),
          'created_by': uid,
          'created_at': _now(),
        });
        try {
          if (pid != null && pid.isNotEmpty) {
            await db.rawDelete(
              'DELETE FROM product_serials WHERE product_id = ? AND '
              'lower(serial) = lower(?)',
              [pid, v],
            );
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
}

// ── المشتريات ──

Future<void> _recalcOrder(Database db, String orderId) async {
  final items = await db.query(
    'purchase_order_items',
    where: 'purchase_order_id = ?',
    whereArgs: [orderId],
  );
  var sub = 0.0, disc = 0.0, tax = 0.0, total = 0.0;
  for (final it in items) {
    final q = _n(it['quantity']);
    final c = _n(it['unit_cost']);
    final d = _n(it['discount']);
    final r = _n(it['tax_rate']);
    var line = q * c - d;
    if (line < 0) line = 0;
    final t = _round2(line * r / 100);
    sub += q * c;
    disc += d;
    tax += t;
    total += line + t;
    await db.update(
      'purchase_order_items',
      {'tax_amount': t, 'total': line + t},
      where: 'id = ?',
      whereArgs: [it['id']],
    );
  }
  await db.update(
    'purchase_orders',
    {
      'subtotal': sub,
      'discount': disc,
      'tax_amount': tax,
      'grand_total': total,
      'updated_at': _now(),
    },
    where: 'id = ?',
    whereArgs: [orderId],
  );
}

Future<void> _recalcPurchInv(Database db, String invId) async {
  final items = await db.query(
    'purchase_invoice_items',
    where: 'purchase_invoice_id = ?',
    whereArgs: [invId],
  );
  var sub = 0.0, disc = 0.0, tax = 0.0, total = 0.0;
  for (final it in items) {
    final q = _n(it['quantity']);
    final c = _n(it['unit_cost']);
    final d = _n(it['discount']);
    final r = _n(it['tax_rate']);
    var line = q * c - d;
    if (line < 0) line = 0;
    final t = _round2(line * r / 100);
    sub += q * c;
    disc += d;
    tax += t;
    total += line + t;
    await db.update(
      'purchase_invoice_items',
      {'tax_amount': t, 'total': line + t},
      where: 'id = ?',
      whereArgs: [it['id']],
    );
  }
  final taxable = (sub - disc) < 0 ? 0.0 : (sub - disc);
  await db.update(
    'purchase_invoices',
    {
      'subtotal': sub,
      'discount': disc,
      'taxable_amount': taxable,
      'tax_amount': tax,
      'grand_total': total,
      'updated_at': _now(),
    },
    where: 'id = ?',
    whereArgs: [invId],
  );
}

void _purchaseRpc() {
  LocalRpc.register('recalc_purchase_order', (db, p) async {
    final id = p['p_order'] as String?;
    if (id == null || id.isEmpty) throw StateError('ORDER_NOT_FOUND');
    await _recalcOrder(db, id);
    return null;
  });

  LocalRpc.register('recalc_purchase_invoice', (db, p) async {
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    await _recalcPurchInv(db, id);
    return null;
  });

  LocalRpc.register('submit_purchase_order', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['purchases.create', 'purchases.edit'],
    );
    final id = p['p_order'] as String?;
    if (id == null || id.isEmpty) throw StateError('ORDER_NOT_FOUND');
    final o = await _one(db, 'purchase_orders', id);
    if (o == null) throw StateError('ORDER_NOT_FOUND');
    if ('${o['status']}' != 'DRAFT') throw StateError('INVALID_STATUS');
    if ((o['supplier_id'] as String?)?.isEmpty != false) {
      throw StateError('SUPPLIER_REQUIRED');
    }
    if ((o['warehouse_id'] as String?)?.isEmpty != false) {
      throw StateError('WAREHOUSE_REQUIRED');
    }
    final items = await db.query(
      'purchase_order_items',
      columns: ['id'],
      where: 'purchase_order_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (items.isEmpty) throw StateError('EMPTY_ORDER');
    await _recalcOrder(db, id);
    await db.update(
      'purchase_orders',
      {'status': 'ORDERED', 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'STATUS_CHANGE', 'PURCHASE_ORDER', id,
        {'from': 'DRAFT'}, {'to': 'ORDERED'});
    return null;
  });

  LocalRpc.register('receive_purchase_order', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['purchases.create', 'purchases.edit'],
    );
    final id = p['p_order'] as String?;
    if (id == null || id.isEmpty) throw StateError('ORDER_NOT_FOUND');
    final o = await _one(db, 'purchase_orders', id);
    if (o == null) throw StateError('ORDER_NOT_FOUND');
    final st = '${o['status']}';
    if (st != 'ORDERED' && st != 'PARTIALLY_RECEIVED') {
      throw StateError('INVALID_STATUS');
    }
    final rawLines = p['p_lines'];
    final lines = rawLines is List ? rawLines : const [];
    if (lines.isEmpty) throw StateError('EMPTY_LINES');
    final wh = o['warehouse_id'] as String?;
    final notes = p['p_notes'] as String?;
    for (final e in lines) {
      final m = Map<String, dynamic>.from(e as Map);
      final itemId = '${m['item_id'] ?? ''}';
      final qty = _n(m['qty']);
      final rows = await db.query(
        'purchase_order_items',
        where: 'id = ? AND purchase_order_id = ?',
        whereArgs: [itemId, id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('ITEM_NOT_FOUND');
      final it = rows.first;
      if (qty <= 0) throw StateError('INVALID_QTY');
      final rest = _n(it['quantity']) - _n(it['received_quantity']);
      if (qty > rest) {
        throw StateError('OVER_RECEIVE: ${it['product_name']}');
      }
      await db.update(
        'purchase_order_items',
        {'received_quantity': _n(it['received_quantity']) + qty},
        where: 'id = ?',
        whereArgs: [itemId],
      );
      final pid = it['product_id'] as String?;
      if (pid != null && pid.isNotEmpty && wh != null && wh.isNotEmpty) {
        await _applyPurchaseCost(db, pid, qty, _n(it['unit_cost']));
        final before = await _ensureStock(db, wh, pid);
        await db.rawUpdate(
          'UPDATE warehouse_stock SET quantity = quantity + ?, '
          'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
          [qty, _now(), wh, pid],
        );
        await db.insert('stock_movements', {
          'id': LocalDatabase.newId(),
          'warehouse_id': wh,
          'product_id': pid,
          'movement_type': 'PURCHASE',
          'quantity': qty,
          'before_quantity': before.$1,
          'after_quantity': before.$1 + qty,
          'reference_type': 'PURCHASE_ORDER',
          'reference_id': id,
          'created_by': uid,
          'notes': notes,
          'created_at': _now(),
        });
        await _checkStockLevels(db, wh, pid);
      }
    }
    final rest = await db.rawQuery(
      'SELECT COALESCE(SUM(quantity - received_quantity), 0) AS r '
      'FROM purchase_order_items WHERE purchase_order_id = ?',
      [id],
    );
    final done = _n(rest.first['r']) <= 0;
    await db.update(
      'purchase_orders',
      {
        'status': done ? 'RECEIVED' : 'PARTIALLY_RECEIVED',
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'RECEIVE', 'PURCHASE_ORDER', id,
        {'from': st}, {'to': done ? 'RECEIVED' : 'PARTIALLY_RECEIVED'});
    return null;
  });

  LocalRpc.register('submit_purchase_invoice', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['purchases.create', 'purchases.edit'],
    );
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'purchase_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    final st = '${inv['status']}';
    if (st != 'DRAFT' && st != 'REJECTED') {
      throw StateError('INVALID_STATUS');
    }
    final sid = inv['supplier_id'] as String?;
    if (sid != null && sid.isNotEmpty) {
      final s = await _one(db, 'suppliers', sid);
      if (s != null) {
        await db.update(
          'purchase_invoices',
          {
            'supplier_name_snapshot': s['name'],
            'supplier_phone_snapshot': s['phone'],
            'supplier_tax_number_snapshot': s['tax_number'],
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } else if (((inv['supplier_name_snapshot'] as String?) ?? '')
        .isEmpty) {
      throw StateError('SUPPLIER_REQUIRED');
    }
    if ((inv['warehouse_id'] as String?)?.isEmpty != false) {
      throw StateError('WAREHOUSE_REQUIRED');
    }
    final items = await db.query(
      'purchase_invoice_items',
      columns: ['id'],
      where: 'purchase_invoice_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (items.isEmpty) throw StateError('EMPTY_INVOICE');
    await _recalcPurchInv(db, id);
    await db.update(
      'purchase_invoices',
      {
        'status': 'PENDING_APPROVAL',
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'STATUS_CHANGE', 'PURCHASE_INVOICE', id,
        {'from': st}, {'to': 'PENDING_APPROVAL'});
    return null;
  });

  LocalRpc.register('approve_purchase_invoice', (db, p) async {
    final uid = await _requireAuth(db, one: 'purchases.approve');
    final id = p['p_invoice'] as String?;
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'purchase_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'PENDING_APPROVAL') {
      throw StateError('INVALID_STATUS');
    }
    if ('${inv['created_by']}' == uid &&
        !await _isCompanyManager(db, uid)) {
      throw StateError(
        'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة',
      );
    }
    await _recalcPurchInv(db, id);
    await db.update(
      'purchase_invoices',
      {
        'status': 'APPROVED',
        'approved_by': uid,
        'approved_at': _now(),
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // تسوية تلقائية لغير الآجل.
    final head = await _one(db, 'purchase_invoices', id);
    final total = _n(head?['grand_total']);
    var method = '';
    final hmid = head?['payment_method_id'] as String?;
    if (hmid != null && hmid.isNotEmpty) {
      final m = await _one(db, 'payment_methods', hmid);
      method = '${m?['code'] ?? ''}';
    }
    if (method.isNotEmpty && method != 'CREDIT') {
      var paid = 0.0;
      try {
        final r = await db.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
          "WHERE purchase_invoice_id = ? AND status = 'COMPLETED'",
          [id],
        );
        paid = _n(r.first['s']);
      } catch (_) {}
      if (total - paid > 0) {
        await db.insert('payments', {
          'id': LocalDatabase.newId(),
          'payment_number': await _docNumber(
            db,
            'payments',
            'payment_number',
            'PAY',
            6,
            true,
          ),
          'supplier_id': head?['supplier_id'],
          'purchase_invoice_id': id,
          'payment_method_id': hmid,
          'amount': total - paid,
          'payment_date': _today(),
          'status': 'COMPLETED',
          'notes': 'سداد تلقائي - $method',
          'created_by': uid,
          'created_at': _now(),
        });
      }
    }
    await _refreshPurchPayStatus(db, id);
    // زيادة المخزون للفواتير المباشرة فقط (المرتبطة بطلب تتخطى).
    final poId = head?['purchase_order_id'] as String?;
    final wh = head?['warehouse_id'] as String?;
    if ((poId == null || poId.isEmpty) && wh != null && wh.isNotEmpty) {
      final items = await db.query(
        'purchase_invoice_items',
        where: 'purchase_invoice_id = ?',
        whereArgs: [id],
      );
      for (final it in items) {
        final pid = it['product_id'] as String?;
        final qty = _n(it['quantity']);
        if (pid == null || pid.isEmpty || qty <= 0) continue;
        final before = await _ensureStock(db, wh, pid);
        await db.rawUpdate(
          'UPDATE warehouse_stock SET quantity = quantity + ?, '
          'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
          [qty, _now(), wh, pid],
        );
        await db.insert('stock_movements', {
          'id': LocalDatabase.newId(),
          'warehouse_id': wh,
          'product_id': pid,
          'movement_type': 'PURCHASE',
          'quantity': qty,
          'before_quantity': before.$1,
          'after_quantity': before.$1 + qty,
          'reference_type': 'PURCHASE_INVOICE',
          'reference_id': id,
          'created_by': uid,
          'notes': 'اعتماد فاتورة مشتريات',
          'created_at': _now(),
        });
        await _checkStockLevels(db, wh, pid);
      }
    }
    await _audit(db, uid, 'APPROVE', 'PURCHASE_INVOICE', id,
        {'from': 'PENDING_APPROVAL'}, {'to': 'APPROVED'});
    return null;
  });

  LocalRpc.register('reject_purchase_invoice', (db, p) async {
    final uid = await _requireAuth(db, one: 'purchases.approve');
    final id = p['p_invoice'] as String?;
    final reason = ((p['p_reason'] as String?) ?? '').trim();
    if (reason.isEmpty) throw StateError('REASON_REQUIRED');
    if (id == null || id.isEmpty) throw StateError('INVOICE_NOT_FOUND');
    final inv = await _one(db, 'purchase_invoices', id);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'PENDING_APPROVAL') {
      throw StateError('INVALID_STATUS');
    }
    if ('${inv['created_by']}' == uid) {
      throw StateError(
        'CANNOT_APPROVE_OWN: لا تملك صلاحية اعتماد هذه الفاتورة',
      );
    }
    await db.update(
      'purchase_invoices',
      {
        'status': 'REJECTED',
        'rejected_by': uid,
        'rejected_at': _now(),
        'rejection_reason': reason,
        'approved_by': null,
        'approved_at': null,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'REJECT', 'PURCHASE_INVOICE', id,
        {'from': 'PENDING_APPROVAL'}, {'to': 'REJECTED'});
    return null;
  });
}

// ── المرتجعات ──

/// المتبقي القابل للإرجاع per صنف: الفوترة − المكتمل.
Future<Map<String, double>> _salesRemaining(
  Database db,
  String invId,
) async {
  final out = <String, double>{};
  try {
    final items = await db.query(
      'sales_invoice_items',
      columns: ['product_id', 'quantity'],
      where: 'sales_invoice_id = ?',
      whereArgs: [invId],
    );
    for (final it in items) {
      final k = (it['product_id'] as String?) ?? '__null__';
      out[k] = (out[k] ?? 0) + _n(it['quantity']);
    }
    final rets = await db.rawQuery(
      '''SELECT i.product_id AS pid, COALESCE(SUM(i.quantity), 0) AS q
         FROM sales_return_items i
         JOIN sales_returns r ON r.id = i.sales_return_id
         WHERE r.sales_invoice_id = ? AND r.status = 'COMPLETED'
         GROUP BY i.product_id''',
      [invId],
    );
    for (final r in rets) {
      final k = (r['pid'] as String?) ?? '__null__';
      out[k] = (out[k] ?? 0) - _n(r['q']);
    }
  } catch (_) {}
  return out;
}

Future<Map<String, double>> _purchRemaining(
  Database db,
  String invId,
) async {
  final out = <String, double>{};
  try {
    final items = await db.query(
      'purchase_invoice_items',
      columns: ['product_id', 'quantity'],
      where: 'purchase_invoice_id = ?',
      whereArgs: [invId],
    );
    for (final it in items) {
      final k = (it['product_id'] as String?) ?? '__null__';
      out[k] = (out[k] ?? 0) + _n(it['quantity']);
    }
    final rets = await db.rawQuery(
      '''SELECT i.product_id AS pid, COALESCE(SUM(i.quantity), 0) AS q
         FROM purchase_return_items i
         JOIN purchase_returns r ON r.id = i.purchase_return_id
         WHERE r.purchase_invoice_id = ? AND r.status = 'COMPLETED'
         GROUP BY i.product_id''',
      [invId],
    );
    for (final r in rets) {
      final k = (r['pid'] as String?) ?? '__null__';
      out[k] = (out[k] ?? 0) - _n(r['q']);
    }
  } catch (_) {}
  return out;
}

/// حد المرتجع بالساعات من السياسة (null/غائب/سالب = بلا حد).
Future<double?> _returnWindowHours(Database db, bool sales) async {
  try {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['return_policy'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['value'];
    final d = raw is String ? jsonDecode(raw) : raw;
    if (d is! Map) return null;
    final v = d[sales ? 'sales_window_hours' : 'purchase_window_hours'];
    if (v == null) return null;
    final h = v is num ? v.toDouble() : double.tryParse('$v');
    if (h == null || h < 0) return null;
    return h;
  } catch (_) {
    return null;
  }
}

void _returnsRpc() {
  LocalRpc.register('sales_returnable', (db, p) async {
    final invId = p['p_invoice'] as String?;
    if (invId == null || invId.isEmpty) return [];
    final groups = <String, Map<String, dynamic>>{};
    try {
      final items = await db.query(
        'sales_invoice_items',
        where: 'sales_invoice_id = ?',
        whereArgs: [invId],
      );
      for (final it in items) {
        final k = (it['product_id'] as String?) ?? '__null__';
        final g = groups[k] ??= {
          'product_id': it['product_id'],
          'item_name': it['item_name'],
          'sku': it['sku'],
          'unit_price': _n(it['unit_price']),
          'tax_rate': _n(it['tax_rate']),
          'invoiced_qty': 0.0,
        };
        g['invoiced_qty'] = (g['invoiced_qty'] as double) + _n(it['quantity']);
        // min لنفس التجميع (مثل السيرفر).
        if ('${it['item_name'] ?? ''}'
            .compareTo('${g['item_name'] ?? ''}') < 0) {
          g['item_name'] = it['item_name'];
        }
        if (_n(it['unit_price']) < (g['unit_price'] as double)) {
          g['unit_price'] = _n(it['unit_price']);
        }
      }
      final rem = await _salesRemaining(db, invId);
      final inv = <String, double>{};
      for (final it in items) {
        final k = (it['product_id'] as String?) ?? '__null__';
        inv[k] = (inv[k] ?? 0) + _n(it['quantity']);
      }
      final out = <Map<String, dynamic>>[];
      for (final e in groups.entries) {
        final invoiced = inv[e.key] ?? 0.0;
        final remaining = rem[e.key] ?? invoiced;
        final returned = invoiced - remaining;
        final left = remaining < 0 ? 0.0 : remaining;
        out.add({
          'product_id': e.value['product_id'],
          'item_name': e.value['item_name'],
          'sku': e.value['sku'],
          'unit_price': e.value['unit_price'],
          'tax_rate': e.value['tax_rate'],
          'invoiced_qty': invoiced,
          'returned_qty': returned < 0 ? 0.0 : returned,
          'remaining_qty': left,
        });
      }
      out.sort((a, b) =>
          '${a['item_name']}'.compareTo('${b['item_name']}'));
      return out;
    } catch (_) {
      return [];
    }
  });

  LocalRpc.register('purchase_returnable', (db, p) async {
    final invId = p['p_invoice'] as String?;
    if (invId == null || invId.isEmpty) return [];
    try {
      final items = await db.query(
        'purchase_invoice_items',
        where: 'purchase_invoice_id = ?',
        whereArgs: [invId],
      );
      final groups = <String, Map<String, dynamic>>{};
      final inv = <String, double>{};
      for (final it in items) {
        final k = (it['product_id'] as String?) ?? '__null__';
        inv[k] = (inv[k] ?? 0) + _n(it['quantity']);
        final g = groups[k] ??= {
          'product_id': it['product_id'],
          'item_name': it['product_name_snapshot'],
          'sku': it['sku_snapshot'],
          'unit_cost': _n(it['unit_cost']),
          'tax_rate': _n(it['tax_rate']),
        };
        if (_n(it['unit_cost']) < (g['unit_cost'] as double)) {
          g['unit_cost'] = _n(it['unit_cost']);
        }
      }
      final rem = await _purchRemaining(db, invId);
      final out = <Map<String, dynamic>>[];
      for (final e in groups.entries) {
        final invoiced = inv[e.key] ?? 0.0;
        final remaining = rem[e.key] ?? invoiced;
        final returned = invoiced - remaining;
        final left = remaining < 0 ? 0.0 : remaining;
        out.add({
          'product_id': e.value['product_id'],
          'item_name': e.value['item_name'],
          'sku': e.value['sku'],
          'unit_cost': e.value['unit_cost'],
          'tax_rate': e.value['tax_rate'],
          'invoiced_qty': invoiced,
          'returned_qty': returned < 0 ? 0.0 : returned,
          'remaining_qty': left,
        });
      }
      out.sort((a, b) =>
          '${a['item_name']}'.compareTo('${b['item_name']}'));
      return out;
    } catch (_) {
      return [];
    }
  });

  LocalRpc.register('complete_sales_return', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final id = p['p_id'] as String?;
    if (id == null || id.isEmpty) throw StateError('NOT_FOUND');
    final ret = await _one(db, 'sales_returns', id);
    if (ret == null) throw StateError('NOT_FOUND');
    if ('${ret['status']}' != 'DRAFT') throw StateError('INVALID_STATUS');
    final wh = ret['warehouse_id'] as String?;
    if (wh == null || wh.isEmpty) throw StateError('WAREHOUSE_REQUIRED');
    // نافذة المرتجع من سياسة التطبيق.
    final invId = ret['sales_invoice_id'] as String?;
    final window = await _returnWindowHours(db, true);
    if (window != null && window >= 0 && invId != null && invId.isNotEmpty) {
      final inv = await _one(db, 'sales_invoices', invId);
      final created = DateTime.tryParse('${inv?['created_at']}');
      if (created != null &&
          DateTime.now().difference(created).inHours >
              window + 1e-9) {
        throw StateError(
          'RETURN_WINDOW_EXPIRED: انتهت مدة المرتجع لهذه الفاتورة '
          '(المسموح $window ساعة من إنشائها)',
        );
      }
    }
    final items = await db.query(
      'sales_return_items',
      where: 'sales_return_id = ?',
      whereArgs: [id],
    );
    if (items.isEmpty) throw StateError('EMPTY_LINES');
    final rem = invId == null || invId.isEmpty
        ? <String, double>{}
        : await _salesRemaining(db, invId);
    var sub = 0.0, tax = 0.0, total = 0.0;
    for (final it in items) {
      final q = _n(it['quantity']);
      if (q <= 0) throw StateError('INVALID_QTY');
      final k = (it['product_id'] as String?) ?? '__null__';
      if (rem.isNotEmpty && q > (rem[k] ?? 0) + 1e-9) {
        throw StateError('OVER_RETURN: ${it['item_name']}');
      }
      final pr = _n(it['unit_price']);
      final r = _n(it['tax_rate']);
      final line = q * pr;
      final t = _round2(line * r / 100);
      sub += line;
      tax += t;
      total += line + t;
      await db.update(
        'sales_return_items',
        {'tax_amount': t, 'total': line + t},
        where: 'id = ?',
        whereArgs: [it['id']],
      );
    }
    // زيادة المخزون + حركة SALES_RETURN.
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      if (!await _tracked(db, pid)) continue;
      final qty = _n(it['quantity']);
      final before = await _ensureStock(db, wh, pid);
      await db.rawUpdate(
        'UPDATE warehouse_stock SET quantity = quantity + ?, '
        'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
        [qty, _now(), wh, pid],
      );
      await db.insert('stock_movements', {
        'id': LocalDatabase.newId(),
        'warehouse_id': wh,
        'product_id': pid,
        'movement_type': 'SALES_RETURN',
        'quantity': qty,
        'before_quantity': before.$1,
        'after_quantity': before.$1 + qty,
        'reference_type': 'SALES_RETURN',
        'reference_id': id,
        'created_by': uid,
        'created_at': _now(),
      });
      await _checkStockLevels(db, wh, pid);
    }
    await db.update(
      'sales_returns',
      {
        'subtotal': sub,
        'tax_amount': tax,
        'grand_total': total,
        'status': 'COMPLETED',
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'COMPLETE', 'SALES_RETURN', id,
        {'from': 'DRAFT'}, {'to': 'COMPLETED'});
    return null;
  });

  LocalRpc.register('complete_purchase_return', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['purchases.create', 'purchases.edit'],
    );
    final id = p['p_id'] as String?;
    if (id == null || id.isEmpty) throw StateError('NOT_FOUND');
    final ret = await _one(db, 'purchase_returns', id);
    if (ret == null) throw StateError('NOT_FOUND');
    if ('${ret['status']}' != 'DRAFT') throw StateError('INVALID_STATUS');
    final wh = ret['warehouse_id'] as String?;
    if (wh == null || wh.isEmpty) throw StateError('WAREHOUSE_REQUIRED');
    final invId = ret['purchase_invoice_id'] as String?;
    final window = await _returnWindowHours(db, false);
    if (window != null && window >= 0 && invId != null && invId.isNotEmpty) {
      final inv = await _one(db, 'purchase_invoices', invId);
      final created = DateTime.tryParse('${inv?['created_at']}');
      if (created != null &&
          DateTime.now().difference(created).inHours >
              window + 1e-9) {
        throw StateError(
          'RETURN_WINDOW_EXPIRED: انتهت مدة المرتجع لهذه الفاتورة '
          '(المسموح $window ساعة من إنشائها)',
        );
      }
    }
    final items = await db.query(
      'purchase_return_items',
      where: 'purchase_return_id = ?',
      whereArgs: [id],
    );
    if (items.isEmpty) throw StateError('EMPTY_LINES');
    final rem = invId == null || invId.isEmpty
        ? <String, double>{}
        : await _purchRemaining(db, invId);
    var sub = 0.0, tax = 0.0, total = 0.0;
    for (final it in items) {
      final q = _n(it['quantity']);
      if (q <= 0) throw StateError('INVALID_QTY');
      final k = (it['product_id'] as String?) ?? '__null__';
      if (rem.isNotEmpty && q > (rem[k] ?? 0) + 1e-9) {
        throw StateError('OVER_RETURN: ${it['product_name']}');
      }
      final c = _n(it['unit_cost']);
      final r = _n(it['tax_rate']);
      final line = q * c;
      final t = _round2(line * r / 100);
      sub += line;
      tax += t;
      total += line + t;
      await db.update(
        'purchase_return_items',
        {'tax_amount': t, 'total': line + t},
        where: 'id = ?',
        whereArgs: [it['id']],
      );
    }
    // نقص المخزون + حركة PURCHASE_RETURN (لازم رصيد كافٍ).
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      if (!await _tracked(db, pid)) continue;
      final qty = _n(it['quantity']);
      final s = await db.query(
        'warehouse_stock',
        columns: ['quantity'],
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [wh, pid],
        limit: 1,
      );
      final before = s.isEmpty ? 0.0 : _n(s.first['quantity']);
      if (before < qty) {
        throw StateError('INSUFFICIENT_STOCK: ${it['product_name']}');
      }
      await db.rawUpdate(
        'UPDATE warehouse_stock SET quantity = quantity - ?, '
        'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
        [qty, _now(), wh, pid],
      );
      await db.insert('stock_movements', {
        'id': LocalDatabase.newId(),
        'warehouse_id': wh,
        'product_id': pid,
        'movement_type': 'PURCHASE_RETURN',
        'quantity': qty,
        'before_quantity': before,
        'after_quantity': before - qty,
        'reference_type': 'PURCHASE_RETURN',
        'reference_id': id,
        'created_by': uid,
        'created_at': _now(),
      });
      await _checkStockLevels(db, wh, pid);
    }
    await db.update(
      'purchase_returns',
      {
        'subtotal': sub,
        'tax_amount': tax,
        'grand_total': total,
        'status': 'COMPLETED',
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'COMPLETE', 'PURCHASE_RETURN', id,
        {'from': 'DRAFT'}, {'to': 'COMPLETED'});
    return null;
  });
}

// ── المخازن ──

void _stockRpc() {
  LocalRpc.register('create_stock_adjustment', (db, p) async {
    final uid = await _requireAuth(db, one: 'inventory.adjust');
    final wh = p['p_warehouse_id'] as String?;
    final pid = p['p_product_id'] as String?;
    final change = _n(p['p_qty_change']);
    final notes = p['p_notes'] as String?;
    if (p['p_qty_change'] == null || change == 0) {
      throw StateError('INVALID_QTY');
    }
    final w = wh == null ? null : await _one(db, 'warehouses', wh);
    if (w == null || (w['is_active'] != 1 && w['is_active'] != true)) {
      throw StateError('WAREHOUSE_NOT_FOUND');
    }
    final pr = pid == null ? null : await _one(db, 'products', pid);
    if (pr == null || (pr['is_active'] != 1 && pr['is_active'] != true)) {
      throw StateError('PRODUCT_NOT_FOUND');
    }
    var s = await db.query(
      'warehouse_stock',
      columns: ['id', 'quantity'],
      where: 'warehouse_id = ? AND product_id = ?',
      whereArgs: [wh, pid],
      limit: 1,
    );
    if (s.isEmpty) {
      if (change < 0) throw StateError('INSUFFICIENT_STOCK');
      final sid = LocalDatabase.newId();
      await db.insert('warehouse_stock', {
        'id': sid,
        'warehouse_id': wh,
        'product_id': pid,
        'quantity': 0,
        'reserved_quantity': 0,
        'updated_at': _now(),
      });
      s = await db.query(
        'warehouse_stock',
        columns: ['id', 'quantity'],
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [wh, pid],
        limit: 1,
      );
    }
    final before = _n(s.first['quantity']);
    final after = before + change;
    if (after < 0) throw StateError('INSUFFICIENT_STOCK');
    final sid = '${s.first['id']}';
    await db.update(
      'warehouse_stock',
      {'quantity': after, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [sid],
    );
    await db.insert('stock_movements', {
      'id': LocalDatabase.newId(),
      'warehouse_id': wh,
      'product_id': pid,
      'movement_type': change > 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
      'quantity': change.abs(),
      'before_quantity': before,
      'after_quantity': after,
      'reference_type': 'STOCK_ADJUSTMENT',
      'reference_id': sid,
      'created_by': uid,
      'notes': notes,
      'created_at': _now(),
    });
    await _checkStockLevels(db, wh!, pid!);
    await _audit(db, uid, 'STOCK_ADJUSTMENT', 'WAREHOUSE_STOCK', sid,
        {'before': before}, {'after': after, 'change': change});
    return sid;
  });

  LocalRpc.register('create_stock_transfer', (db, p) async {
    final uid = await _requireAuth(db, one: 'inventory.transfer');
    final from = p['p_from_warehouse'] as String?;
    final to = p['p_to_warehouse'] as String?;
    final pid = p['p_product_id'] as String?;
    final qty = _n(p['p_quantity']);
    final notes = p['p_notes'] as String?;
    if (from == to) throw StateError('SAME_WAREHOUSE');
    if (p['p_quantity'] == null || qty <= 0) throw StateError('INVALID_QTY');
    final s = await db.query(
      'warehouse_stock',
      columns: ['quantity', 'reserved_quantity'],
      where: 'warehouse_id = ? AND product_id = ?',
      whereArgs: [from, pid],
      limit: 1,
    );
    if (s.isEmpty) throw StateError('INSUFFICIENT_STOCK');
    final srcQ = _n(s.first['quantity']);
    final srcR = _n(s.first['reserved_quantity']);
    if (srcQ - srcR < qty) throw StateError('INSUFFICIENT_STOCK');
    await db.rawUpdate(
      'UPDATE warehouse_stock SET quantity = quantity - ?, '
      'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
      [qty, _now(), from, pid],
    );
    final dstBefore = await _ensureStock(db, to!, pid!);
    await db.rawUpdate(
      'UPDATE warehouse_stock SET quantity = quantity + ?, '
      'updated_at = ? WHERE warehouse_id = ? AND product_id = ?',
      [qty, _now(), to, pid],
    );
    await db.insert('stock_movements', {
      'id': LocalDatabase.newId(),
      'warehouse_id': from,
      'product_id': pid,
      'movement_type': 'TRANSFER_OUT',
      'quantity': qty,
      'before_quantity': srcQ,
      'after_quantity': srcQ - qty,
      'reference_type': 'STOCK_TRANSFER',
      'created_by': uid,
      'notes': notes,
      'created_at': _now(),
    });
    await db.insert('stock_movements', {
      'id': LocalDatabase.newId(),
      'warehouse_id': to,
      'product_id': pid,
      'movement_type': 'TRANSFER_IN',
      'quantity': qty,
      'before_quantity': dstBefore.$1,
      'after_quantity': dstBefore.$1 + qty,
      'reference_type': 'STOCK_TRANSFER',
      'created_by': uid,
      'notes': notes,
      'created_at': _now(),
    });
    await _checkStockLevels(db, from!, pid);
    await _checkStockLevels(db, to, pid);
    await _audit(db, uid, 'STOCK_TRANSFER', 'WAREHOUSE_STOCK', pid, null,
        {'from': from, 'to': to, 'qty': qty});
    return null;
  });
}

// ── المدفوعات والأرصدة ──

void _paymentsRpc() {
  LocalRpc.register('create_payment', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'purchases.create'],
    );
    var customerId = p['p_customer_id'] as String?;
    var supplierId = p['p_supplier_id'] as String?;
    final salesId = p['p_sales_invoice_id'] as String?;
    final purchId = p['p_purchase_invoice_id'] as String?;
    final methodId = p['p_method_id'] as String?;
    final amount = _n(p['p_amount']);
    final ref = p['p_reference'] as String?;
    final notes = p['p_notes'] as String?;
    if (p['p_amount'] == null || amount <= 0) {
      throw StateError('INVALID_AMOUNT');
    }
    if (salesId != null &&
        salesId.isNotEmpty &&
        purchId != null &&
        purchId.isNotEmpty) {
      throw StateError('ONE_INVOICE_ONLY');
    }
    // وراثة الطرف من الفاتورة + تسوية القديم (0033).
    if (salesId != null && salesId.isNotEmpty &&
        (customerId == null || customerId.isEmpty)) {
      final inv = await _one(db, 'sales_invoices', salesId);
      customerId = inv?['customer_id'] as String?;
    }
    if (purchId != null && purchId.isNotEmpty &&
        (supplierId == null || supplierId.isEmpty)) {
      final inv = await _one(db, 'purchase_invoices', purchId);
      supplierId = inv?['supplier_id'] as String?;
    }
    try {
      await db.rawUpdate(
        '''UPDATE payments SET customer_id =
             (SELECT customer_id FROM sales_invoices
              WHERE sales_invoices.id = payments.sales_invoice_id)
           WHERE sales_invoice_id IS NOT NULL AND customer_id IS NULL''',
      );
      await db.rawUpdate(
        '''UPDATE payments SET supplier_id =
             (SELECT supplier_id FROM purchase_invoices
              WHERE purchase_invoices.id = payments.purchase_invoice_id)
           WHERE purchase_invoice_id IS NOT NULL AND supplier_id IS NULL''',
      );
    } catch (_) {}
    final pid = LocalDatabase.newId();
    await db.insert('payments', {
      'id': pid,
      'payment_number': await _docNumber(
        db,
        'payments',
        'payment_number',
        'PAY',
        6,
        true,
      ),
      'customer_id': customerId,
      'supplier_id': supplierId,
      'sales_invoice_id': salesId,
      'purchase_invoice_id': purchId,
      'payment_method_id': methodId,
      'amount': amount,
      'transaction_reference': ref,
      'payment_date': _today(),
      'status': 'COMPLETED',
      'notes': notes,
      'created_by': uid,
      'created_at': _now(),
    });
    String? entity;
    String? entityId;
    if (salesId != null && salesId.isNotEmpty) {
      await _refreshSalesPayStatus(db, salesId);
      entity = 'SALES_INVOICE';
      entityId = salesId;
    } else if (purchId != null && purchId.isNotEmpty) {
      await _refreshPurchPayStatus(db, purchId);
      entity = 'PURCHASE_INVOICE';
      entityId = purchId;
    }
    await _audit(db, uid, 'PAYMENT', entity ?? 'PAYMENT', entityId ?? pid,
        null, {'payment': pid, 'amount': amount});
    return pid;
  });

  /// رصيد عميل per فاتورة (0033): total/paid/outstanding.
  LocalRpc.register('customer_balance', (db, p) async {
    final id = p['p_customer'] as String?;
    if (id == null || id.isEmpty) return [];
    try {
      final invs = await db.query(
        'sales_invoices',
        columns: ['id', 'grand_total'],
        where: 'customer_id = ? AND status IN (?, ?)',
        whereArgs: [id, 'APPROVED', 'PENDING_APPROVAL'],
      );
      var total = 0.0, paid = 0.0, out = 0.0;
      for (final inv in invs) {
        final t = _n(inv['grand_total']);
        total += t;
        var py = 0.0;
        try {
          final r = await db.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
            "WHERE sales_invoice_id = ? AND status = 'COMPLETED'",
            [inv['id']],
          );
          py = _n(r.first['s']);
        } catch (_) {}
        var rt = 0.0;
        try {
          final r = await db.rawQuery(
            '''SELECT COALESCE(SUM(i.total), 0) AS s
               FROM sales_return_items i
               JOIN sales_returns r ON r.id = i.sales_return_id
               WHERE r.sales_invoice_id = ? AND r.status = 'COMPLETED' ''',
            [inv['id']],
          );
          rt = _n(r.first['s']);
        } catch (_) {}
        paid += py;
        final left = t - py - rt;
        out += left < 0 ? 0 : left;
      }
      return [
        {'total': total, 'paid': paid, 'outstanding': out}
      ];
    } catch (_) {
      return [];
    }
  });

  LocalRpc.register('supplier_balance', (db, p) async {
    final id = p['p_supplier'] as String?;
    if (id == null || id.isEmpty) return [];
    try {
      final invs = await db.query(
        'purchase_invoices',
        columns: ['id', 'grand_total'],
        where: 'supplier_id = ? AND status IN (?, ?)',
        whereArgs: [id, 'APPROVED', 'PENDING_APPROVAL'],
      );
      var total = 0.0, paid = 0.0, out = 0.0;
      for (final inv in invs) {
        final t = _n(inv['grand_total']);
        total += t;
        var py = 0.0;
        try {
          final r = await db.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
            "WHERE purchase_invoice_id = ? AND status = 'COMPLETED'",
            [inv['id']],
          );
          py = _n(r.first['s']);
        } catch (_) {}
        var rt = 0.0;
        try {
          final r = await db.rawQuery(
            '''SELECT COALESCE(SUM(i.total), 0) AS s
               FROM purchase_return_items i
               JOIN purchase_returns r ON r.id = i.purchase_return_id
               WHERE r.purchase_invoice_id = ?
               AND r.status = 'COMPLETED' ''',
            [inv['id']],
          );
          rt = _n(r.first['s']);
        } catch (_) {}
        paid += py;
        final left = t - py - rt;
        out += left < 0 ? 0 : left;
      }
      return [
        {'total': total, 'paid': paid, 'outstanding': out}
      ];
    } catch (_) {
      return [];
    }
  });

  Future<double> totalOutstanding(
    Database db,
    bool sales,
  ) async {
    var out = 0.0;
    try {
      final invTable = sales ? 'sales_invoices' : 'purchase_invoices';
      final payCol = sales ? 'sales_invoice_id' : 'purchase_invoice_id';
      final invs = await db.query(
        invTable,
        columns: ['id', 'grand_total'],
        where: 'status IN (?, ?)',
        whereArgs: ['APPROVED', 'PENDING_APPROVAL'],
      );
      for (final inv in invs) {
        final t = _n(inv['grand_total']);
        var py = 0.0;
        try {
          final r = await db.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS s FROM payments '
            "WHERE $payCol = ? AND status = 'COMPLETED'",
            [inv['id']],
          );
          py = _n(r.first['s']);
        } catch (_) {}
        var rt = 0.0;
        try {
          final retTable =
              sales ? 'sales_returns' : 'purchase_returns';
          final retItems =
              sales ? 'sales_return_items' : 'purchase_return_items';
          final retLink =
              sales ? 'sales_invoice_id' : 'purchase_invoice_id';
          final retId =
              sales ? 'sales_return_id' : 'purchase_return_id';
          final r = await db.rawQuery(
            '''SELECT COALESCE(SUM(i.total), 0) AS s FROM $retItems i
               JOIN $retTable r ON r.id = i.$retId
               WHERE r.$retLink = ? AND r.status = 'COMPLETED' ''',
            [inv['id']],
          );
          rt = _n(r.first['s']);
        } catch (_) {}
        final left = t - py - rt;
        if (left > 0) out += left;
      }
    } catch (_) {}
    return out;
  }

  LocalRpc.register('total_customer_outstanding', (db, p) async {
    return totalOutstanding(db, true);
  });
  LocalRpc.register('total_supplier_outstanding', (db, p) async {
    return totalOutstanding(db, false);
  });
}

// ── الشحن ──

void _shippingRpc() {
  LocalRpc.register('ship_shipment', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final id = p['p_id'] as String?;
    if (id == null || id.isEmpty) throw StateError('NOT_FOUND');
    final s = await _one(db, 'shipments', id);
    if (s == null) throw StateError('NOT_FOUND');
    if ('${s['status']}' != 'PREPARING') throw StateError('INVALID_STATUS');
    final invId = s['sales_invoice_id'] as String?;
    if (invId == null || invId.isEmpty) {
      await db.update(
        'shipments',
        {'status': 'SHIPPED', 'shipped_at': _now(), 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );
      return null;
    }
    final inv = await _one(db, 'sales_invoices', invId);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'APPROVED') {
      throw StateError('INVOICE_NOT_APPROVED');
    }
    final wh = inv['warehouse_id'] as String?;
    if (wh == null || wh.isEmpty) throw StateError('WAREHOUSE_REQUIRED');
    final items = await db.query(
      'sales_invoice_items',
      where: 'sales_invoice_id = ?',
      whereArgs: [invId],
    );
    for (final it in items) {
      final pid = it['product_id'] as String?;
      if (pid == null || pid.isEmpty) continue;
      if (!await _tracked(db, pid)) continue;
      final qty = _n(it['quantity']);
      final row = await db.query(
        'warehouse_stock',
        columns: ['quantity', 'reserved_quantity'],
        where: 'warehouse_id = ? AND product_id = ?',
        whereArgs: [wh, pid],
        limit: 1,
      );
      if (row.isEmpty) {
        throw StateError('STOCK_NOT_FOUND: ${it['item_name']}');
      }
      final q = _n(row.first['quantity']);
      final r = _n(row.first['reserved_quantity']);
      if (q < qty) throw StateError('INSUFFICIENT_STOCK: ${it['item_name']}');
      if (r < qty) throw StateError('NOT_RESERVED: ${it['item_name']}');
      await db.rawUpdate(
        'UPDATE warehouse_stock SET quantity = quantity - ?, '
        'reserved_quantity = reserved_quantity - ?, updated_at = ? '
        'WHERE warehouse_id = ? AND product_id = ?',
        [qty, qty, _now(), wh, pid],
      );
      await db.insert('stock_movements', {
        'id': LocalDatabase.newId(),
        'warehouse_id': wh,
        'product_id': pid,
        'movement_type': 'SALE',
        'quantity': qty,
        'before_quantity': q,
        'after_quantity': q - qty,
        'reference_type': 'SALES_INVOICE',
        'reference_id': invId,
        'created_by': uid,
        'notes': 'ship ${s['shipment_number']}',
        'created_at': _now(),
      });
      await _checkStockLevels(db, wh, pid);
    }
    await db.update(
      'shipments',
      {'status': 'SHIPPED', 'shipped_at': _now(), 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'STATUS_CHANGE', 'SHIPMENT', id,
        {'from': 'PREPARING'}, {'to': 'SHIPPED'});
    return null;
  });

  LocalRpc.register('deliver_shipment', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final id = p['p_id'] as String?;
    if (id == null || id.isEmpty) throw StateError('NOT_FOUND');
    final s = await _one(db, 'shipments', id);
    if (s == null) throw StateError('NOT_FOUND');
    if ('${s['status']}' != 'SHIPPED') throw StateError('INVALID_STATUS');
    await db.update(
      'shipments',
      {
        'status': 'DELIVERED',
        'delivered_at': _now(),
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, uid, 'STATUS_CHANGE', 'SHIPMENT', id,
        {'from': 'SHIPPED'}, {'to': 'DELIVERED'});
    return null;
  });
}

// ── السيريال ──

void _serialsRpc() {
  LocalRpc.register('verify_serial', (db, p) async {
    final uid = _uid();
    if (uid == null || uid.isEmpty) throw StateError('NOT_AUTHENTICATED');
    if (!await _isActiveUser(db, uid)) throw StateError('INACTIVE_USER');
    final perms = await _permsOf(db, uid);
    if (!perms.contains('serials.verify') &&
        !perms.contains('users.manage')) {
      throw StateError('NO_PERMISSION: serials.verify required');
    }
    final serial = ((p['p_serial'] as String?) ?? '').trim();
    if (serial.isEmpty) return [];
    try {
      final rows = await db.rawQuery(
        'SELECT * FROM serial_sales WHERE lower(serial) = lower(?) '
        'ORDER BY sold_at DESC LIMIT 1',
        [serial],
      );
      if (rows.isEmpty) return [];
      final r = rows.first;
      final out = Map<String, dynamic>.from(r);
      final pid = r['product_id'] as String?;
      if (pid != null && pid.isNotEmpty) {
        final pr = await _one(db, 'products', pid);
        out['product_name'] =
            (r['product_name_snapshot'] as String?)?.isNotEmpty == true
                ? r['product_name_snapshot']
                : pr?['name'];
        out['brand'] = pr?['brand'];
        out['model'] = pr?['model'];
      } else {
        out['product_name'] = r['product_name_snapshot'];
      }
      final cid = r['customer_id'] as String?;
      if (cid != null && cid.isNotEmpty) {
        final c = await _one(db, 'customers', cid);
        out['customer_name'] =
            (r['customer_name_snapshot'] as String?)?.isNotEmpty == true
                ? r['customer_name_snapshot']
                : c?['name'];
        out['customer_phone'] =
            (r['customer_phone_snapshot'] as String?)?.isNotEmpty == true
                ? r['customer_phone_snapshot']
                : c?['phone'];
      } else {
        out['customer_name'] = r['customer_name_snapshot'];
        out['customer_phone'] = r['customer_phone_snapshot'];
      }
      final invId = r['sales_invoice_id'] as String?;
      if (invId != null && invId.isNotEmpty) {
        final inv = await _one(db, 'sales_invoices', invId);
        out['invoice_number'] = inv?['invoice_number'];
      }
      return [out];
    } catch (_) {
      return [];
    }
  });

  LocalRpc.register('register_serial_sale', (db, p) async {
    final uid = await _requireAuth(
      db,
      anyOf: const ['sales.create', 'sales.edit'],
    );
    final itemId = p['p_item_id'] as String?;
    final serial = ((p['p_serial'] as String?) ?? '').trim();
    final notes = p['p_notes'] as String?;
    if (serial.isEmpty) throw StateError('SERIAL_REQUIRED');
    final it = itemId == null
        ? null
        : await _one(db, 'sales_invoice_items', itemId);
    if (it == null) throw StateError('ITEM_NOT_FOUND');
    final invId = it['sales_invoice_id'] as String?;
    final inv = invId == null ? null : await _one(db, 'sales_invoices', invId);
    if (inv == null) throw StateError('INVOICE_NOT_FOUND');
    if ('${inv['status']}' != 'APPROVED') {
      throw StateError(
        'INVOICE_NOT_APPROVED: سجل السيريالات بعد اعتماد الفاتورة',
      );
    }
    try {
      final ex = await db.query(
        'serial_sales',
        columns: ['id'],
        where: 'serial = ?',
        whereArgs: [serial],
        limit: 1,
      );
      if (ex.isNotEmpty) {
        throw StateError('SERIAL_ALREADY_SOLD: السيريال ده متسجل بيع قبل كده');
      }
    } catch (e) {
      if (e is StateError) rethrow;
    }
    final pid = it['product_id'] as String?;
    final sid = LocalDatabase.newId();
    await db.insert('serial_sales', {
      'id': sid,
      'serial': serial,
      'product_id': pid,
      'product_name_snapshot': it['item_name'],
      'customer_id': inv['customer_id'],
      'customer_name_snapshot': inv['customer_name_snapshot'],
      'customer_phone_snapshot': inv['customer_phone_snapshot'],
      'sales_invoice_id': invId,
      'sales_invoice_item_id': itemId,
      'unit_price': _n(it['unit_price']),
      'unit_cost': _n(it['unit_cost']),
      'sold_at': _now(),
      'notes': notes,
      'created_by': uid,
      'created_at': _now(),
    });
    try {
      if (pid != null && pid.isNotEmpty) {
        await db.delete(
          'product_serials',
          where: 'product_id = ? AND serial = ?',
          whereArgs: [pid, serial],
        );
      }
    } catch (_) {}
    await _audit(db, uid, 'CREATE', 'SERIAL_SALE', sid);
    return sid;
  });
}

// ── الصيانة ──

void _maintenanceRpc() {
  LocalRpc.register('reset_all_data_keep_users', (db, p) async {
    final uid = await _requireAuth(db, one: 'users.manage');
    const tables = [
      'sales_return_items',
      'sales_returns',
      'purchase_return_items',
      'purchase_returns',
      'payments',
      'shipments',
      'sales_invoice_items',
      'sales_invoices',
      'purchase_invoice_items',
      'purchase_invoices',
      'purchase_order_items',
      'purchase_orders',
      'warehouse_stock',
      'stock_movements',
      'stock_alerts',
      'shortages',
      'product_serials',
      'serial_sales',
      'product_barcodes',
      'products',
      'customer_addresses',
      'customers',
      'suppliers',
      'warehouses',
      'attachments',
      'audit_logs',
    ];
    for (final t in tables) {
      try {
        await db.delete(t);
      } catch (_) {}
    }
    // تصفير عدّادات الأرقام.
    try {
      await db.delete(
        'app_settings',
        where: 'key LIKE ?',
        whereArgs: ['seq_%'],
      );
    } catch (_) {}
    await _audit(db, uid, 'RESET', 'ALL_DATA', 'ALL', null, {
      'kept': 'users/roles/permissions/settings',
    });
    return {'ok': true};
  });
}
