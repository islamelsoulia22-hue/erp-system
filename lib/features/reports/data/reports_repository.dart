import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../shipping/domain/shipping.dart' show Payment;

class DashboardStats {
  final double salesTotal;
  final double purchasesTotal;
  final int pendingSales;
  final int pendingPurchases;
  final int lowStockCount;
  final int pendingShipments;

  const DashboardStats({
    required this.salesTotal,
    required this.purchasesTotal,
    required this.pendingSales,
    required this.pendingPurchases,
    required this.lowStockCount,
    required this.pendingShipments,
  });
}

/// Dense KPI set for the ERP home dashboard.
/// Each query degrades to zero when the user lacks permission,
/// so every role sees a consistent dashboard.
class ErpKpis {
  final double salesTotal;
  final double purchasesTotal;
  final double inventoryValue;
  final double customerOutstanding;
  final double supplierOutstanding;
  final double netProfitMonth;

  const ErpKpis({
    required this.salesTotal,
    required this.purchasesTotal,
    required this.inventoryValue,
    required this.customerOutstanding,
    required this.supplierOutstanding,
    this.netProfitMonth = 0,
  });

  const ErpKpis.empty()
      : salesTotal = 0,
        purchasesTotal = 0,
        inventoryValue = 0,
        customerOutstanding = 0,
        supplierOutstanding = 0,
        netProfitMonth = 0;
}

class ReportsRepository {
  final dynamic _client;
  ReportsRepository(this._client);

  Future<DashboardStats> managerStats() async {
    try {
      double sum(List rows, String key) {
        var t = 0.0;
        for (final r in rows) {
          final v = (r as Map)[key];
          if (v is num) {
            t += v.toDouble();
          } else {
            t += double.tryParse(v?.toString() ?? '') ?? 0;
          }
        }
        return t;
      }

      final sales = (await _client
          .from('sales_invoices')
          .select('grand_total')
          .eq('status', 'APPROVED')) as List;
      final purchases = (await _client
          .from('purchase_invoices')
          .select('grand_total')
          .eq('status', 'APPROVED')) as List;
      final pSales = (await _client
          .from('sales_invoices')
          .select('id')
          .eq('status', 'PENDING_APPROVAL')) as List;
      final pPurch = (await _client
          .from('purchase_invoices')
          .select('id')
          .eq('status', 'PENDING_APPROVAL')) as List;
      final low = (await _client
          .from('low_stock_products')
          .select('product_id')) as List;
      final ship = (await _client
          .from('shipments')
          .select('id')
          .eq('status', 'PREPARING')) as List;

      return DashboardStats(
        salesTotal: sum(sales, 'grand_total'),
        purchasesTotal: sum(purchases, 'grand_total'),
        pendingSales: pSales.length,
        pendingPurchases: pPurch.length,
        lowStockCount: low.length,
        pendingShipments: ship.length,
      );
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> lowStock({int limit = 20}) async {
    try {
      final rows = (await _client
          .from('low_stock_products')
          .select()
          .limit(limit)) as List;
      return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<double> _sum(
      String table, String column, Map<String, dynamic> filters) async {
    try {
      var q = _client.from(table).select(column);
      filters.forEach((k, v) => q = q.eq(k, v));
      final rows = (await q) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)[column]);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Dashboard KPIs. Permission-gated queries degrade gracefully.
  /// إجمالي المبيعات/المشتريات والمستحقات كلها بالصافي بعد المرتجع.
  /// المستحقات = مجموع مستحق كل فاتورة (لا فاتورة تسحب التانية بالسالب).
  Future<ErpKpis> dashboardKpis() async {
    final sales = await _sum(
        'sales_invoices', 'grand_total', {'status': 'APPROVED'});
    final purchases = await _sum(
        'purchase_invoices', 'grand_total', {'status': 'APPROVED'});
    final salesRet = await salesReturnsGrandAll();
    final purchRet = await purchaseReturnsGrandAll();
    final custOut = await _totalOutstanding(
        'total_customer_outstanding',
        sales - await _sumSalesPayments() - salesRet);
    final suppOut = await _totalOutstanding(
        'total_supplier_outstanding',
        purchases - await _sumPurchPayments() - purchRet);
    final stockValue = await _inventoryValue();
    double monthNet = 0;
    try {
      final now = DateTime.now();
      final p = await profitRange(
          from: DateTime(now.year, now.month, 1),
          to: DateTime(now.year, now.month + 1, 0));
      // صافي ربح المبيعات (بيع - شراء) بدون خصم المصاريف حسب طلب العميل.
      monthNet = p.gross;
    } catch (_) {}
    return ErpKpis(
      salesTotal:
          (sales - salesRet).clamp(0, double.infinity),
      purchasesTotal:
          (purchases - purchRet).clamp(0, double.infinity),
      inventoryValue: stockValue,
      customerOutstanding: custOut,
      supplierOutstanding: suppOut,
      netProfitMonth: monthNet,
    );
  }

  /// إجمالي المستحقات من السيرفر (per فاتورة)، مع fallback للحسبة القديمة.
  Future<double> _totalOutstanding(
      String fn, double fallback) async {
    try {
      final res = await _client.rpc(fn);
      final dynamic v;
      if (res is List && res.isNotEmpty) {
        v = (res.first as Map).values.first;
      } else {
        v = res;
      }
      if (v is num) return v.toDouble().clamp(0, double.infinity);
      return (double.tryParse('$v') ?? fallback)
          .clamp(0, double.infinity);
    } catch (_) {
      return fallback.clamp(0, double.infinity);
    }
  }

  Future<double> _sumSalesPayments() async {
    try {
      final rows = (await _client
          .from('payments')
          .select('amount')
          .eq('status', 'COMPLETED')
          .not('sales_invoice_id', 'is', null)) as List;
      return rows.fold<double>(
          0.0, (s, r) => s + _num((r as Map)['amount']));
    } catch (_) {
      return 0;
    }
  }

  Future<double> _sumPurchPayments() async {
    try {
      final rows = (await _client
          .from('payments')
          .select('amount')
          .eq('status', 'COMPLETED')
          .not('purchase_invoice_id', 'is', null)) as List;
      return rows.fold<double>(
          0.0, (s, r) => s + _num((r as Map)['amount']));
    } catch (_) {
      return 0;
    }
  }

  /// قيمة المخزون على الكمية **المتاحة** (الكلي − المحجوز) × سعر الشراء،
  /// لأن المحجوز مرتبط بفواتير معتمدة ولم يعد متاحا للبيع.
  Future<double> _inventoryValue() async {
    try {
      final rows = (await _client.from('warehouse_stock').select(
              'quantity, reserved_quantity, available_quantity, products!inner(purchase_price)')) as List;
      var total = 0.0;
      for (final r in rows) {
        final m = r as Map;
        final p = m['products'];
        final price =
            p is Map ? _num(p['purchase_price']) : 0.0;
        var avail = _num(m['available_quantity']);
        if (m['available_quantity'] == null) {
          avail = _num(m['quantity']) -
              _num(m['reserved_quantity']);
        }
        if (avail < 0) avail = 0;
        total += avail * price;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Latest audit entries for the activity feed.
  /// Returns [] when the role may not read the log.
  Future<List<Map<String, dynamic>>> recentActivity(
      {int limit = 8}) async {
    try {
      final rows = (await _client
          .from('audit_logs')
          .select('action, entity_type, created_at')
          .order('created_at', ascending: false)
          .limit(limit)) as List;
      return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
    } catch (_) {
      return [];
    }
  }

  // ---------- Periodic + partner reports ----------

  static String _dayStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();

  static String _nextDay(DateTime d) => DateTime(d.year, d.month, d.day)
      .add(const Duration(days: 1))
      .toIso8601String();

  /// فواتير مبيعات معتمدة في مدى + عميل اختياري.
  Future<List<ReportInvoice>> approvedSales({
    required DateTime from,
    required DateTime to,
    String? customerId,
  }) async {
    try {
      var req = _client.from('sales_invoices').select(
          'id, invoice_number, customer_name_snapshot, grand_total, tax_amount, created_at, customers ( name )');
      req = req.eq('status', 'APPROVED');
      if (customerId != null && customerId.isNotEmpty) {
        req = req.eq('customer_id', customerId);
      }
      req = req
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .order('created_at')
          .range(0, 999);
      final rows = (await req) as List;
      return [
        for (final r in rows)
          ReportInvoice.fromSales(
              Map<String, dynamic>.from(r as Map))
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// فواتير مشتريات معتمدة في مدى + مورد اختياري.
  Future<List<ReportInvoice>> approvedPurchases({
    required DateTime from,
    required DateTime to,
    String? supplierId,
  }) async {
    try {
      var req = _client.from('purchase_invoices').select(
          'id, invoice_number, supplier_name_snapshot, grand_total, tax_amount, created_at, suppliers ( name )');
      req = req.eq('status', 'APPROVED');
      if (supplierId != null && supplierId.isNotEmpty) {
        req = req.eq('supplier_id', supplierId);
      }
      req = req
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .order('created_at')
          .range(0, 999);
      final rows = (await req) as List;
      return [
        for (final r in rows)
          ReportInvoice.fromPurchase(
              Map<String, dynamic>.from(r as Map))
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مدفوعات مكتملة بتاريخ الدفع في مدى (للتحصيل والمدفوع).
  Future<List<Payment>> paymentsInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('payments')
          .select('*, payment_methods ( code ), sales_invoices ( invoice_number, customer_name_snapshot ), purchase_invoices ( invoice_number, supplier_name_snapshot )')
          .eq('status', 'COMPLETED')
          .gte('payment_date', _dayStart(from))
          .lt('payment_date', _nextDay(to))
          .order('payment_date')
          .range(0, 999)) as List;
      return rows
          .map((e) => Payment.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مدفوعات مكتملة مرتبطة بفواتير معينة (لكشف الحساب — كل الفترات).
  Future<List<Payment>> paymentsForSales(
      List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) return [];
    try {
      final rows = (await _client
          .from('payments')
          .select('*, payment_methods ( code ), sales_invoices ( invoice_number, customer_name_snapshot ), purchase_invoices ( invoice_number, supplier_name_snapshot )')
          .eq('status', 'COMPLETED')
          .inFilter('sales_invoice_id', invoiceIds)
          .order('payment_date')
          .range(0, 999)) as List;
      return rows
          .map((e) => Payment.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  Future<List<Payment>> paymentsForPurchases(
      List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) return [];
    try {
      final rows = (await _client
          .from('payments')
          .select('*, payment_methods ( code ), sales_invoices ( invoice_number, customer_name_snapshot ), purchase_invoices ( invoice_number, supplier_name_snapshot )')
          .eq('status', 'COMPLETED')
          .inFilter('purchase_invoice_id', invoiceIds)
          .order('payment_date')
          .range(0, 999)) as List;
      return rows
          .map((e) => Payment.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------- Profits phase 3 ----------

  /// تكلفة البضاعة المباعة: مجموع (الكمية × لقطة التكلفة)
  /// لسطور فواتير معينة. البنود الخاصة (بدون تكلفة) مستبعدة.
  Future<double> cogsForInvoices(List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) return 0;
    try {
      var total = 0.0;
      // دفعات لتفادي حدود طول الاستعلام.
      for (var i = 0; i < invoiceIds.length; i += 100) {
        final chunk = invoiceIds.sublist(
            i,
            i + 100 > invoiceIds.length
                ? invoiceIds.length
                : i + 100);
        final rows = (await _client
            .from('sales_invoice_items')
            .select('quantity, unit_cost')
            .inFilter('sales_invoice_id', chunk)
            .range(0, 999)) as List;
        for (final r in rows) {
          final m = r as Map;
          total += _num(m['quantity']) * _num(m['unit_cost']);
        }
      }
      return total;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مرتجعات مبيعات مكتملة في مدى (تخصم من الإيراد).
  /// ترجع صافي قيمة المرتجع بدون ضريبة (سعر البيع فقط).
  Future<double> salesReturnsTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select('grand_total, tax_amount')
          .eq('status', 'COMPLETED')
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .range(0, 999)) as List;
      var total = 0.0;
      for (final r in rows) {
        final m = r as Map;
        total += _num(m['grand_total']) - _num(m['tax_amount']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// قيمة المرتجعات بالإجمالي (شامل الضريبة) في مدى — للتبويب المالي.
  Future<double> salesReturnsGrandTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select('grand_total')
          .eq('status', 'COMPLETED')
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .range(0, 999)) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)['grand_total']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// مستندات مرتجعات المبيعات المكتملة في مدى (للعرض في التبويب المالي).
  Future<List<Map<String, dynamic>>> salesReturnDocs({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select(
              'id, return_number, grand_total, created_at, customers ( name )')
          .eq('status', 'COMPLETED')
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .order('created_at')
          .range(0, 999)) as List;
      return [
        for (final r in rows)
          Map<String, dynamic>.from(r as Map)
      ];
    } catch (_) {
      return [];
    }
  }

  /// إجمالي المرتجعات المكتملة (كل الفترات) — لصافي الداشبورد.
  Future<double> salesReturnsGrandAll() async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select('grand_total')
          .eq('status', 'COMPLETED')
          .range(0, 9999)) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)['grand_total']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// مرتجعات مشتريات مكتملة في مدى (تخصم من المشتريات اليومية).
  Future<double> purchaseReturnsTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('purchase_returns')
          .select('grand_total')
          .eq('status', 'COMPLETED')
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .range(0, 999)) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)['grand_total']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<double> purchaseReturnsGrandAll() async {
    try {
      final rows = (await _client
          .from('purchase_returns')
          .select('grand_total')
          .eq('status', 'COMPLETED')
          .range(0, 9999)) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)['grand_total']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// تكلفة البضاعة الراجعة من المرتجعات المكتملة في مدى.
  /// بتتضاف للربح (البضاعة رجعت المخزن) عشان صافي ربح المبيعات
  /// = (البيع - الشراء) - (المرتجع بيع - المرتجع تكلفة).
  /// التكلفة من لقطة الفاتورة الأصلية لو مربوطة، وإلا المتوسط الحالي.
  Future<double> salesReturnsCost({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rets = (await _client
          .from('sales_returns')
          .select('id, sales_invoice_id')
          .eq('status', 'COMPLETED')
          .gte('created_at', _dayStart(from))
          .lt('created_at', _nextDay(to))
          .range(0, 999)) as List;
      if (rets.isEmpty) return 0;
      final retIds = [
        for (final r in rets) (r as Map)['id'] as String
      ];
      final linkOf = <String, String?>{};
      for (final r in rets) {
        final m = r as Map;
        linkOf[m['id'] as String] =
            m['sales_invoice_id'] as String?;
      }
      // بنود المرتجعات.
      var retItems = <Map>[];
      for (var i = 0; i < retIds.length; i += 100) {
        final chunk = retIds.sublist(
            i, i + 100 > retIds.length ? retIds.length : i + 100);
        final rows = (await _client
            .from('sales_return_items')
            .select('sales_return_id, product_id, quantity')
            .inFilter('sales_return_id', chunk)
            .range(0, 999)) as List;
        retItems.addAll([for (final r in rows) Map.from(r as Map)]);
      }
      if (retItems.isEmpty) return 0;
      // لقطات التكلفة من الفواتير الأصلية المربوطة.
      final linkedInvIds = {
        for (final v in linkOf.values)
          if (v != null && v.isNotEmpty) v
      }.toList();
      final costOf = <String, double>{};
      if (linkedInvIds.isNotEmpty) {
        for (var i = 0; i < linkedInvIds.length; i += 100) {
          final chunk = linkedInvIds.sublist(i,
              i + 100 > linkedInvIds.length ? linkedInvIds.length : i + 100);
          final rows = (await _client
              .from('sales_invoice_items')
              .select('sales_invoice_id, product_id, unit_cost')
              .inFilter('sales_invoice_id', chunk)
              .range(0, 999)) as List;
          for (final r in rows) {
            final m = r as Map;
            final pid = m['product_id'];
            if (pid == null) continue;
            costOf['${m['sales_invoice_id']}|$pid'] =
                _num(m['unit_cost']);
          }
        }
      }
      // المتوسط الحالي للأصناف غير المربوطة.
      final needAvg = <String>{};
      for (final it in retItems) {
        final pid = it['product_id'] as String?;
        if (pid == null) continue;
        final rid = it['sales_return_id'] as String?;
        final invId = rid == null ? null : linkOf[rid];
        final key =
            invId == null ? null : '$invId|$pid';
        if (key == null || !costOf.containsKey(key)) {
          needAvg.add(pid);
        }
      }
      final avgOf = <String, double>{};
      if (needAvg.isNotEmpty) {
        final ids = needAvg.toList();
        for (var i = 0; i < ids.length; i += 100) {
          final chunk = ids.sublist(i,
              i + 100 > ids.length ? ids.length : i + 100);
          final rows = (await _client
              .from('products')
              .select('id, average_cost, purchase_price')
              .inFilter('id', chunk)
              .range(0, 999)) as List;
          for (final r in rows) {
            final m = r as Map;
            final avg = _num(m['average_cost']);
            avgOf[m['id'] as String] =
                avg > 0 ? avg : _num(m['purchase_price']);
          }
        }
      }
      var total = 0.0;
      for (final it in retItems) {
        final pid = it['product_id'] as String?;
        if (pid == null) continue;
        final qty = _num(it['quantity']);
        final rid = it['sales_return_id'] as String?;
        final invId = rid == null ? null : linkOf[rid];
        double unit = 0;
        if (invId != null && costOf.containsKey('$invId|$pid')) {
          unit = costOf['$invId|$pid']!;
        } else {
          unit = avgOf[pid] ?? 0;
        }
        total += qty * unit;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// حزمة الربحية الكاملة لمدى: إيراد (بدون ضريبة)، تكلفة، مجمل، مصروفات، صافي.
  /// صافي ربح المبيعات = (سعر البيع - سعر الشراء) بدون ضريبة،
  /// وبدون خصم المصاريف (المصاريف معروضة لوحدها).
  Future<ProfitReport> profitRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final sales = await approvedSales(from: from, to: to);
    // الإيراد بدون ضريبة (الضريبة للحكومة مش ربح).
    final salesNet =
        sales.fold(0.0, (s, e) => s + e.netTotal);
    final cogs = await cogsForInvoices(
        [for (final s in sales) s.id]);
    final returns = await salesReturnsTotal(from: from, to: to);
    final returnsCost = await salesReturnsCost(from: from, to: to);
    final revenue = salesNet - returns;
    // نرد تكلفة الراجع للمخزن.
    final double adjCogs =
        (cogs - returnsCost).clamp(0, double.infinity).toDouble();
    final expenses =
        await _expensesPaidTotal(from: from, to: to);
    return ProfitReport(
      revenue: revenue,
      salesTotal: salesNet,
      returnsTotal: returns,
      cogs: adjCogs,
      gross: revenue - adjCogs,
      expenses: expenses,
      net: revenue - adjCogs - expenses,
      invoicesCount: sales.length,
    );
  }

  Future<double> _expensesPaidTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('expenses')
          .select('amount')
          .eq('payment_status', 'PAID')
          .gte('expense_date', _dayStart(from))
          .lt('expense_date', _nextDay(to))
          .range(0, 999)) as List;
      var total = 0.0;
      for (final r in rows) {
        total += _num((r as Map)['amount']);
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// مؤشرات اليوم الحالي: مبيعات/مشتريات اليوم (بالصافي
  /// بعد مرتجعات اليوم) وربح اليوم (مجمل الربحية لنفس اليوم).
  Future<DailyKpis> dailyKpis() async {
    try {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final sales = await approvedSales(from: day, to: day);
      final salesSum =
          sales.fold(0.0, (s, e) => s + e.total);
      final salesRet =
          await salesReturnsGrandTotal(from: day, to: day);
      final purch = await approvedPurchases(
          from: day, to: day);
      final purchSum =
          purch.fold(0.0, (s, e) => s + e.total);
      final purchRet =
          await purchaseReturnsTotal(from: day, to: day);
      double profit = 0;
      try {
        profit = (await profitRange(from: day, to: day)).gross;
      } catch (_) {}
      return DailyKpis(
        salesDay:
            (salesSum - salesRet).clamp(0, double.infinity),
        purchasesDay:
            (purchSum - purchRet).clamp(0, double.infinity),
        profitDay: profit,
      );
    } catch (_) {
      return const DailyKpis(
          salesDay: 0, purchasesDay: 0, profitDay: 0);
    }
  }
}

/// نتيجة حسابات الربحية لمدى زمني.
class ProfitReport {
  final double revenue;
  final double salesTotal;
  final double returnsTotal;
  final double cogs;
  final double gross;
  final double expenses;
  final double net;
  final int invoicesCount;
  const ProfitReport({
    required this.revenue,
    required this.salesTotal,
    required this.returnsTotal,
    required this.cogs,
    required this.gross,
    required this.expenses,
    required this.net,
    required this.invoicesCount,
  });
}

/// مؤشرات اليوم للداشبورد: مبيعات/مشتريات/ربح اليوم.
class DailyKpis {
  final double salesDay;
  final double purchasesDay;
  final double profitDay;
  const DailyKpis({
    required this.salesDay,
    required this.purchasesDay,
    required this.profitDay,
  });
}

/// سطر فاتورة مبسط للتقارير (مبيعات/مشتريات بنفس الشكل).
class ReportInvoice {
  final String id;
  final String number;
  final String partner;
  final double total;
  final double taxAmount;
  final DateTime date;
  const ReportInvoice({
    required this.id,
    required this.number,
    required this.partner,
    required this.total,
    this.taxAmount = 0,
    required this.date,
  });

  /// صافي البيع بدون ضريبة (هو اللي بيتحسب عليه الربح).
  double get netTotal => total - taxAmount;

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory ReportInvoice.fromSales(Map<String, dynamic> m) {
    final c = m['customers'];
    return ReportInvoice(
      id: m['id'] as String,
      number: (m['invoice_number'] as String?) ?? '',
      partner: (m['customer_name_snapshot'] as String?) ??
          (c is Map ? ((c['name'] as String?) ?? 'عميل نقدي') : 'عميل نقدي'),
      total: _n(m['grand_total']),
      taxAmount: _n(m['tax_amount']),
      date: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory ReportInvoice.fromPurchase(Map<String, dynamic> m) {
    final s = m['suppliers'];
    return ReportInvoice(
      id: m['id'] as String,
      number: (m['invoice_number'] as String?) ?? '',
      partner: (m['supplier_name_snapshot'] as String?) ??
          (s is Map ? ((s['name'] as String?) ?? 'مورد') : 'مورد'),
      total: _n(m['grand_total']),
      taxAmount: _n(m['tax_amount']),
      date: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return ReportsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

final managerStatsProvider =
    FutureProvider.autoDispose<DashboardStats>((ref) {
  return ref.watch(reportsRepositoryProvider).managerStats();
});
