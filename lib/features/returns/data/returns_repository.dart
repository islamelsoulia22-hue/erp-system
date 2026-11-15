import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/widgets/app_pagination.dart';
import '../domain/returns.dart';

class ReturnsRepository {
  final dynamic _client;
  ReturnsRepository(this._client);

  Future<List<ReturnDoc>> salesList({int page = 0, int pageSize = AppConstants.pageSize}) async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select('*, customers ( name )')
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) => ReturnDoc.sales(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد مرتجعات المبيعات (لترقيم الصفحات).
  Future<int> countSales() async {
    try {
      final res =
          await _client.from('sales_returns').select('id').count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<ReturnDoc>> purchaseList({int page = 0, int pageSize = AppConstants.pageSize}) async {
    try {
      final rows = (await _client
          .from('purchase_returns')
          .select('*, suppliers ( name )')
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) => ReturnDoc.purchase(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد مرتجعات المشتريات (لترقيم الصفحات).
  Future<int> countPurchases() async {
    try {
      final res =
          await _client.from('purchase_returns').select('id').count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<ReturnDoc?> getSales(String id) async {
    final row = await _client
        .from('sales_returns')
        .select('*, customers ( name )')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return ReturnDoc.sales(Map<String, dynamic>.from(row as Map));
  }

  Future<ReturnDoc?> getPurchase(String id) async {
    final row = await _client
        .from('purchase_returns')
        .select('*, suppliers ( name )')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return ReturnDoc.purchase(
        Map<String, dynamic>.from(row as Map));
  }

  Future<List<ReturnItem>> salesItems(String id) async {
    final rows = (await _client
        .from('sales_return_items')
        .select()
        .eq('sales_return_id', id)) as List;
    return rows
        .map((e) => ReturnItem.sales(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ReturnItem>> purchaseItems(String id) async {
    final rows = (await _client
        .from('purchase_return_items')
        .select()
        .eq('purchase_return_id', id)) as List;
    return rows
        .map((e) => ReturnItem.purchase(
            Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Draft from an approved sales invoice (prefill items, cap enforced on complete).
  Future<String> createSalesReturn({
    required String invoiceId,
    required String warehouseId,
    String? reason,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final inv = await _client
          .from('sales_invoices')
          .select('customer_id')
          .eq('id', invoiceId)
          .maybeSingle();
      final row = await _client
          .from('sales_returns')
          .insert({
            'sales_invoice_id': invoiceId,
            'customer_id': inv == null
                ? null
                : (inv as Map)['customer_id'],
            'warehouse_id': warehouseId,
            'reason': reason,
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (row as Map)['id'] as String;
      await _client.from('sales_return_items').insert([
        for (final it in items)
          {
            'sales_return_id': id,
            'product_id': it['product_id'],
            'item_name': it['name'],
            'sku': it['sku'],
            'quantity': it['qty'],
            'unit_price': it['price'],
            'tax_rate': it['tax'] ?? 0,
          }
      ]);
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createPurchaseReturn({
    required String invoiceId,
    required String warehouseId,
    String? reason,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final inv = await _client
          .from('purchase_invoices')
          .select('supplier_id')
          .eq('id', invoiceId)
          .maybeSingle();
      final row = await _client
          .from('purchase_returns')
          .insert({
            'purchase_invoice_id': invoiceId,
            'supplier_id': inv == null
                ? null
                : (inv as Map)['supplier_id'],
            'warehouse_id': warehouseId,
            'reason': reason,
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (row as Map)['id'] as String;
      await _client.from('purchase_return_items').insert([
        for (final it in items)
          {
            'purchase_return_id': id,
            'product_id': it['product_id'],
            'product_name': it['name'],
            'sku': it['sku'],
            'quantity': it['qty'],
            'unit_cost': it['price'],
            'tax_rate': it['tax'] ?? 0,
          }
      ]);
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> completeSales(String id) =>
      _rpc('complete_sales_return', {'p_id': id});
  Future<void> completePurchase(String id) =>
      _rpc('complete_purchase_return', {'p_id': id});

  /// إنشاء + إتمام مباشر لمرتجع مبيعات (نسخة الجهاز — بدون موافقات).
  /// الإتمام يزيد المخزون تلقائيا.
  Future<String> createAndCompleteSalesReturn({
    required String invoiceId,
    required String warehouseId,
    String? reason,
    required List<Map<String, dynamic>> items,
  }) async {
    final id = await createSalesReturn(
      invoiceId: invoiceId,
      warehouseId: warehouseId,
      reason: reason,
      items: items,
    );
    await completeSales(id);
    return id;
  }

  /// إنشاء + إتمام مباشر لمرتجع مشتريات (نسخة الجهاز — بدون موافقات).
  /// الإتمام يخصم المخزون تلقائيا.
  Future<String> createAndCompletePurchaseReturn({
    required String invoiceId,
    required String warehouseId,
    String? reason,
    required List<Map<String, dynamic>> items,
  }) async {
    final id = await createPurchaseReturn(
      invoiceId: invoiceId,
      warehouseId: warehouseId,
      reason: reason,
      items: items,
    );
    await completePurchase(id);
    return id;
  }

  /// المتبقي القابل للإرجاع per صنف (الفاتورة − المرتجع المكتمل).
  Future<List<Map<String, dynamic>>> salesReturnable(
      String invoiceId) async {
    try {
      final rows = (await _client.rpc('sales_returnable',
          params: {'p_invoice': invoiceId})) as List;
      return [
        for (final r in rows)
          Map<String, dynamic>.from(r as Map)
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> purchaseReturnable(
      String invoiceId) async {
    try {
      final rows = (await _client.rpc('purchase_returnable',
          params: {'p_invoice': invoiceId})) as List;
      return [
        for (final r in rows)
          Map<String, dynamic>.from(r as Map)
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مرتجعات مكتملة/مسودة مرتبطة بفاتورة (للعرض في تفاصيل الفاتورة).
  Future<List<ReturnDoc>> salesReturnsOf(String invoiceId) async {
    try {
      final rows = (await _client
          .from('sales_returns')
          .select('*, customers ( name )')
          .eq('sales_invoice_id', invoiceId)
          .order('created_at', ascending: false)) as List;
      return rows
          .map((e) => ReturnDoc.sales(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<ReturnDoc>> purchaseReturnsOf(
      String invoiceId) async {
    try {
      final rows = (await _client
          .from('purchase_returns')
          .select('*, suppliers ( name )')
          .eq('purchase_invoice_id', invoiceId)
          .order('created_at', ascending: false)) as List;
      return rows
          .map((e) => ReturnDoc.purchase(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  Future<void> _rpc(String fn, Map<String, dynamic> p) async {
    try {
      await _client.rpc(fn, params: p);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// سياسة المرتجعات (المدير فقط يكتب، الكل يقرأ).
  /// null = بدون حد زمني.
  Future<ReturnPolicy> getReturnPolicy() async {
    try {
      final row = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'return_policy')
          .maybeSingle();
      if (row == null) return const ReturnPolicy();
      return ReturnPolicy.fromValue(
          Map<String, dynamic>.from((row as Map)['value'] as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> saveReturnPolicy(ReturnPolicy p) async {
    try {
      await _client.from('app_settings').upsert({
        'key': 'return_policy',
        'value': {
          'sales_window_hours': p.salesWindowHours,
          'purchase_window_hours': p.purchaseWindowHours,
        },
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

/// سياسة المرتجعات: حد المدة بالساعات بعد إنشاء الفاتورة (null = بدون حد).
class ReturnPolicy {
  final double? salesWindowHours;
  final double? purchaseWindowHours;
  const ReturnPolicy(
      {this.salesWindowHours, this.purchaseWindowHours});

  static double? _h(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory ReturnPolicy.fromValue(Map<String, dynamic> m) {
    return ReturnPolicy(
      salesWindowHours: _h(m['sales_window_hours']),
      purchaseWindowHours: _h(m['purchase_window_hours']),
    );
  }

  /// وصف عربي مختصر للمدة (للعرض في الفورم).
  static String describe(double? hours) {
    if (hours == null) return 'بدون حد زمني';
    if (hours < 24) {
      final h = hours.toStringAsFixed(
          hours == hours.truncateToDouble() ? 0 : 1);
      return 'خلال $h ساعة من الفاتورة';
    }
    final d = hours / 24;
    final ds = d.toStringAsFixed(
        d == d.truncateToDouble() ? 0 : 1);
    return 'خلال $ds يوم من الفاتورة';
  }
}

final returnPolicyProvider =
    FutureProvider.autoDispose<ReturnPolicy>((ref) {
  return ref.watch(returnsRepositoryProvider).getReturnPolicy();
});

final returnsRepositoryProvider = Provider<ReturnsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return ReturnsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ReturnsRepository(ref.watch(supabaseClientProvider));
});

final salesReturnsPageProvider = FutureProvider.autoDispose
      .family<PagedData<ReturnDoc>, int>((ref, page) async {
  final repo = ref.watch(returnsRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.salesList(page: page, pageSize: ps),
    repo.countSales(),
  ]);
  return PagedData(res[0] as List<ReturnDoc>, res[1] as int);
});

final purchaseReturnsPageProvider = FutureProvider.autoDispose
      .family<PagedData<ReturnDoc>, int>((ref, page) async {
  final repo = ref.watch(returnsRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.purchaseList(page: page, pageSize: ps),
    repo.countPurchases(),
  ]);
  return PagedData(res[0] as List<ReturnDoc>, res[1] as int);
});
