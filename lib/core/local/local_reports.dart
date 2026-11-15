import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';

class LocalTotals {
  final double salesTotal;
  final double purchasesTotal;
  final double customerOutstanding;
  final double supplierOutstanding;
  final double inventoryValue;
  const LocalTotals({
    required this.salesTotal,
    required this.purchasesTotal,
    required this.customerOutstanding,
    required this.supplierOutstanding,
    required this.inventoryValue,
  });
}

class LocalDailyKpis {
  final double salesDay;
  final double purchasesDay;
  final double profitDay;
  const LocalDailyKpis({
    required this.salesDay,
    required this.purchasesDay,
    required this.profitDay,
  });
}

class LocalReportsRepository {
  final Future<Database> Function() _open;
  LocalReportsRepository(this._open);

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<LocalTotals> totals() async {
    final db = await _open();
    Future<double> sum(String sql, [List<Object?> args = const []]) async {
      final r = await db.rawQuery(sql, args);
      return _n(r.first.values.first);
    }

    final sales = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM sales_invoices WHERE status='APPROVED'",
    );
    final salesRet = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM sales_returns WHERE status='COMPLETED'",
    );
    final purch = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM purchase_invoices WHERE status='APPROVED'",
    );
    final purchRet = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM purchase_returns WHERE status='COMPLETED'",
    );
    final custOut = await sum('''
SELECT COALESCE(SUM(
  MAX(0, i.grand_total - COALESCE((
    SELECT SUM(amount) FROM payments p
    WHERE p.sales_invoice_id = i.id AND p.status = 'COMPLETED'), 0) - COALESCE((
    SELECT SUM(grand_total) FROM sales_returns r
    WHERE r.sales_invoice_id = i.id AND r.status = 'COMPLETED'), 0))
), 0)
FROM sales_invoices i WHERE i.status = 'APPROVED'
''');
    final suppOut = await sum('''
SELECT COALESCE(SUM(
  MAX(0, i.grand_total - COALESCE((
    SELECT SUM(amount) FROM payments p
    WHERE p.purchase_invoice_id = i.id AND p.status = 'COMPLETED'), 0) - COALESCE((
    SELECT SUM(grand_total) FROM purchase_returns r
    WHERE r.purchase_invoice_id = i.id AND r.status = 'COMPLETED'), 0))
), 0)
FROM purchase_invoices i WHERE i.status = 'APPROVED'
''');
    final stock = await sum('''
SELECT COALESCE(SUM(
  MAX(0, s.quantity - s.reserved_quantity) *
  COALESCE(p.purchase_price, 0)), 0)
FROM warehouse_stock s
JOIN products p ON p.id = s.product_id
''');
    return LocalTotals(
      salesTotal: (sales - salesRet).clamp(0, double.infinity),
      purchasesTotal: (purch - purchRet).clamp(0, double.infinity),
      customerOutstanding: custOut,
      supplierOutstanding: suppOut,
      inventoryValue: stock,
    );
  }

  Future<LocalDailyKpis> daily() async {
    final db = await _open();
    final t = _today();
    Future<double> sum(String sql) async {
      final r = await db.rawQuery(sql, [t]);
      return _n(r.first.values.first);
    }

    final salesSum = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM sales_invoices WHERE status='APPROVED' AND substr(created_at,1,10) = ?",
    );
    final salesRet = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM sales_returns WHERE status='COMPLETED' AND substr(created_at,1,10) = ?",
    );
    final purchSum = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM purchase_invoices WHERE status='APPROVED' AND substr(created_at,1,10) = ?",
    );
    final purchRet = await sum(
      "SELECT COALESCE(SUM(grand_total),0) FROM purchase_returns WHERE status='COMPLETED' AND substr(created_at,1,10) = ?",
    );
    // إيراد اليوم بدون ضريبة.
    final salesNet = await sum('''
SELECT COALESCE(SUM(
  (li.quantity * li.unit_price - li.discount)), 0)
FROM sales_invoice_items li
JOIN sales_invoices i ON i.id = li.sales_invoice_id
WHERE i.status = 'APPROVED' AND substr(i.created_at,1,10) = ?
''');
    final retNet = await sum('''
SELECT COALESCE(SUM(li.quantity * li.unit_price), 0)
FROM sales_return_items li
JOIN sales_returns r ON r.id = li.sales_return_id
WHERE r.status = 'COMPLETED' AND substr(r.created_at,1,10) = ?
''');
    final cogs = await sum('''
SELECT COALESCE(SUM(li.quantity * li.unit_cost), 0)
FROM sales_invoice_items li
JOIN sales_invoices i ON i.id = li.sales_invoice_id
WHERE i.status = 'APPROVED' AND substr(i.created_at,1,10) = ?
''');
    final retCost = await sum('''
SELECT COALESCE(SUM(li.quantity * li.unit_cost), 0)
FROM sales_return_items li
JOIN sales_returns r ON r.id = li.sales_return_id
WHERE r.status = 'COMPLETED' AND substr(r.created_at,1,10) = ?
''');
    final revenue = salesNet - retNet;
    final adjCogs = (cogs - retCost).clamp(0, double.infinity);
    return LocalDailyKpis(
      salesDay: (salesSum - salesRet).clamp(0, double.infinity),
      purchasesDay: (purchSum - purchRet).clamp(0, double.infinity),
      profitDay: revenue - adjCogs,
    );
  }
}

final localReportsRepositoryProvider = Provider<LocalReportsRepository>((ref) {
  return LocalReportsRepository(() => LocalDatabase.instance.db);
});

final localTotalsProvider = FutureProvider.autoDispose<LocalTotals>((ref) {
  return ref.watch(localReportsRepositoryProvider).totals();
});

final localDailyProvider = FutureProvider.autoDispose<LocalDailyKpis>((ref) {
  return ref.watch(localReportsRepositoryProvider).daily();
});
