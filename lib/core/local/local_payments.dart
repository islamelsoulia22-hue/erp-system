import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';
import 'local_products.dart' show LocalDataFailure;

class LocalPaymentMethod {
  final String id;
  final String code;
  final String nameAr;
  const LocalPaymentMethod({
    required this.id,
    required this.code,
    required this.nameAr,
  });

  factory LocalPaymentMethod.fromMap(Map<String, Object?> m) {
    return LocalPaymentMethod(
      id: (m['id'] as String?) ?? '',
      code: ((m['code'] as String?) ?? '').toUpperCase(),
      nameAr: (m['name_ar'] as String?) ?? (m['name'] as String?) ?? '',
    );
  }
}

class LocalPayment {
  final String id;
  final double amount;
  final String? methodCode;
  final String? salesInvoiceId;
  final String? purchaseInvoiceId;
  final String? invoiceNumber;
  final String date;
  const LocalPayment({
    required this.id,
    required this.amount,
    this.methodCode,
    this.salesInvoiceId,
    this.purchaseInvoiceId,
    this.invoiceNumber,
    required this.date,
  });

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  factory LocalPayment.fromMap(Map<String, Object?> m) {
    return LocalPayment(
      id: (m['id'] as String?) ?? '',
      amount: _n(m['amount']),
      methodCode: (m['method_code'] as String?)?.toUpperCase(),
      salesInvoiceId: m['sales_invoice_id'] as String?,
      purchaseInvoiceId: m['purchase_invoice_id'] as String?,
      invoiceNumber: (m['invoice_number'] as String?),
      date: (m['created_at'] as String?) ?? '',
    );
  }
}

class LocalPaymentsRepository {
  final Future<Database> Function() _open;
  LocalPaymentsRepository(this._open);

  static const int pageSize = 20;

  Future<List<LocalPaymentMethod>> methods() async {
    final db = await _open();
    final rows = await db.query(
      'payment_methods',
      where: 'is_active = 1',
      orderBy: 'code',
    );
    return [for (final r in rows) LocalPaymentMethod.fromMap(r)];
  }

  /// تسجيل دفعة + تحديث حالة سداد الفاتورة المرتبطة.
  /// يرث الطرف (عميل/مورد) من الفاتورة لو متبعتش.
  Future<String> record({
    String? salesInvoiceId,
    String? purchaseInvoiceId,
    String? customerId,
    String? supplierId,
    required String methodId,
    required double amount,
  }) async {
    if (amount <= 0) {
      throw const LocalDataFailure('ادخل مبلغا أكبر من صفر.');
    }
    if (salesInvoiceId != null && purchaseInvoiceId != null) {
      throw const LocalDataFailure('الدفعة لفاتورة واحدة فقط.');
    }
    final db = await _open();
    final id = LocalDatabase.newId();
    await db.transaction((txn) async {
      if (salesInvoiceId != null && customerId == null) {
        final r = await txn.query(
          'sales_invoices',
          columns: ['customer_id'],
          where: 'id = ?',
          whereArgs: [salesInvoiceId],
          limit: 1,
        );
        if (r.isNotEmpty) {
          customerId = r.first['customer_id'] as String?;
        }
      }
      if (purchaseInvoiceId != null && supplierId == null) {
        final r = await txn.query(
          'purchase_invoices',
          columns: ['supplier_id'],
          where: 'id = ?',
          whereArgs: [purchaseInvoiceId],
          limit: 1,
        );
        if (r.isNotEmpty) {
          supplierId = r.first['supplier_id'] as String?;
        }
      }
      await txn.insert('payments', {
        'id': id,
        'customer_id': customerId,
        'supplier_id': supplierId,
        'sales_invoice_id': salesInvoiceId,
        'purchase_invoice_id': purchaseInvoiceId,
        'payment_method_id': methodId,
        'amount': amount,
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
      });
      if (salesInvoiceId != null) {
        await _refreshStatus(txn, 'sales', salesInvoiceId);
      }
      if (purchaseInvoiceId != null) {
        await _refreshStatus(txn, 'purchase', purchaseInvoiceId);
      }
    });
    return id;
  }

  Future<void> _refreshStatus(
    Transaction txn,
    String kind,
    String invoiceId,
  ) async {
    final table = kind == 'sales' ? 'sales_invoices' : 'purchase_invoices';
    final rows = await txn.query(
      table,
      columns: ['grand_total'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final total = ((rows.first['grand_total'] as num?)?.toDouble() ?? 0);
    final paid = await _paidSum(txn, kind, invoiceId);
    final status = paid <= 0
        ? 'UNPAID'
        : paid < total
        ? 'PARTIAL'
        : 'PAID';
    await txn.update(
      table,
      {'payment_status': status},
      where: 'id = ?',
      whereArgs: [invoiceId],
    );
  }

  Future<double> _paidSum(
    DatabaseExecutor db,
    String kind,
    String invoiceId,
  ) async {
    final col = kind == 'sales' ? 'sales_invoice_id' : 'purchase_invoice_id';
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM payments WHERE $col = ? AND status = 'COMPLETED'",
      [invoiceId],
    );
    return ((rows.first['s'] as num?)?.toDouble() ?? 0);
  }

  /// المدفوع على فاتورة.
  Future<double> invoicePaid({
    String? salesInvoiceId,
    String? purchaseInvoiceId,
  }) async {
    final db = await _open();
    if (salesInvoiceId != null) {
      return _paidSum(db, 'sales', salesInvoiceId);
    }
    return _paidSum(db, 'purchase', purchaseInvoiceId!);
  }

  /// مرتجعات مربوطة بفاتورة (تخصم من المستحق).
  Future<double> invoiceReturns({
    String? salesInvoiceId,
    String? purchaseInvoiceId,
  }) async {
    final db = await _open();
    if (salesInvoiceId != null) {
      final rows = await db.rawQuery(
        "SELECT COALESCE(SUM(grand_total),0) AS s FROM sales_returns WHERE sales_invoice_id = ? AND status = 'COMPLETED'",
        [salesInvoiceId],
      );
      return ((rows.first['s'] as num?)?.toDouble() ?? 0);
    }
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(grand_total),0) AS s FROM purchase_returns WHERE purchase_invoice_id = ? AND status = 'COMPLETED'",
      [purchaseInvoiceId],
    );
    return ((rows.first['s'] as num?)?.toDouble() ?? 0);
  }

  /// مستحق فاتورة = max(0, الإجمالي − المدفوع − المرتجع).
  Future<double> invoiceOutstanding({
    String? salesInvoiceId,
    String? purchaseInvoiceId,
  }) async {
    final db = await _open();
    late final double total;
    if (salesInvoiceId != null) {
      final r = await db.query(
        'sales_invoices',
        columns: ['grand_total'],
        where: 'id = ?',
        whereArgs: [salesInvoiceId],
        limit: 1,
      );
      if (r.isEmpty) return 0;
      total = ((r.first['grand_total'] as num?)?.toDouble() ?? 0);
      final paid = await _paidSum(db, 'sales', salesInvoiceId);
      final ret = await invoiceReturns(salesInvoiceId: salesInvoiceId);
      return (total - paid - ret).clamp(0, double.infinity);
    }
    final r = await db.query(
      'purchase_invoices',
      columns: ['grand_total'],
      where: 'id = ?',
      whereArgs: [purchaseInvoiceId],
      limit: 1,
    );
    if (r.isEmpty) return 0;
    total = ((r.first['grand_total'] as num?)?.toDouble() ?? 0);
    final paid = await _paidSum(db, 'purchase', purchaseInvoiceId!);
    final ret = await invoiceReturns(purchaseInvoiceId: purchaseInvoiceId);
    return (total - paid - ret).clamp(0, double.infinity);
  }

  /// إجمالي مستحقات عميل/مورد (مجموع مستحق كل فاتورة).
  Future<double> partnerOutstanding({
    String? customerId,
    String? supplierId,
  }) async {
    final db = await _open();
    var out = 0.0;
    if (customerId != null) {
      final invs = await db.query(
        'sales_invoices',
        columns: ['id'],
        where: 'customer_id = ? AND status = ?',
        whereArgs: [customerId, 'APPROVED'],
      );
      for (final inv in invs) {
        out += await invoiceOutstanding(salesInvoiceId: inv['id'] as String);
      }
    }
    if (supplierId != null) {
      final invs = await db.query(
        'purchase_invoices',
        columns: ['id'],
        where: 'supplier_id = ? AND status = ?',
        whereArgs: [supplierId, 'APPROVED'],
      );
      for (final inv in invs) {
        out += await invoiceOutstanding(purchaseInvoiceId: inv['id'] as String);
      }
    }
    return out;
  }

  Future<({List<LocalPayment> items, int total})> page({int page = 0}) async {
    final db = await _open();
    final totalRows = await db.rawQuery('SELECT COUNT(*) AS c FROM payments');
    final total = (totalRows.first['c'] as num?)?.toInt() ?? 0;
    final rows = await db.rawQuery(
      '''
SELECT p.*, m.code AS method_code,
  COALESCE(si.invoice_number, pi.invoice_number) AS invoice_number
FROM payments p
LEFT JOIN payment_methods m ON m.id = p.payment_method_id
LEFT JOIN sales_invoices si ON si.id = p.sales_invoice_id
LEFT JOIN purchase_invoices pi ON pi.id = p.purchase_invoice_id
ORDER BY p.created_at DESC
LIMIT ? OFFSET ?
''',
      [pageSize, page * pageSize],
    );
    return (
      items: [for (final r in rows) LocalPayment.fromMap(r)],
      total: total,
    );
  }
}

final localPaymentsRepositoryProvider = Provider<LocalPaymentsRepository>((
  ref,
) {
  return LocalPaymentsRepository(() => LocalDatabase.instance.db);
});

final localPaymentMethodsProvider =
    FutureProvider.autoDispose<List<LocalPaymentMethod>>((ref) {
      return ref.watch(localPaymentsRepositoryProvider).methods();
    });

final localPaymentsPageProvider = FutureProvider.autoDispose
    .family<({List<LocalPayment> items, int total}), int>((ref, page) {
      return ref.watch(localPaymentsRepositoryProvider).page(page: page);
    });

/// مستحق فاتورة (للشاشات).
final localInvoiceOutstandingProvider = FutureProvider.autoDispose
    .family<double, ({bool sales, String id})>((ref, args) {
      final repo = ref.watch(localPaymentsRepositoryProvider);
      return args.sales
          ? repo.invoiceOutstanding(salesInvoiceId: args.id)
          : repo.invoiceOutstanding(purchaseInvoiceId: args.id);
    });
