import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/sales.dart';

const _invSelect = '''
id, invoice_number, reference_number, customer_id,
customer_name_snapshot, warehouse_id, status, payment_status,
payment_method_id, subtotal, discount, tax_amount, grand_total,
created_by, rejection_reason, created_at,
customers ( name ), payment_methods ( code, name, name_ar )
''';

class SalesRepository {
  final dynamic _client;
  SalesRepository(this._client);

  Future<List<SalesInvoice>> list({
    String query = '',
    String? status,
    int page = 0,
    int pageSize = AppConstants.pageSize,
    String? customerId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      var req = _client.from('sales_invoices').select(_invSelect);
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      if (customerId != null && customerId.isNotEmpty) {
        req = req.eq('customer_id', customerId);
      }
      if (from != null) {
        req = req.gte('created_at',
            DateTime(from.year, from.month, from.day).toIso8601String());
      }
      if (to != null) {
        final end =
            DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
        req = req.lt('created_at', end.toIso8601String());
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'invoice_number.ilike.%$q%,reference_number.ilike.%$q%,customer_name_snapshot.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) =>
              SalesInvoice.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد فواتير المبيعات المطابقة (لترقيم الصفحات — نفس فلاتر [list]).
  Future<int> count({
    String query = '',
    String? status,
    String? customerId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      var req = _client.from('sales_invoices').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      if (customerId != null && customerId.isNotEmpty) {
        req = req.eq('customer_id', customerId);
      }
      if (from != null) {
        req = req.gte('created_at',
            DateTime(from.year, from.month, from.day).toIso8601String());
      }
      if (to != null) {
        final end =
            DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
        req = req.lt('created_at', end.toIso8601String());
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'invoice_number.ilike.%$q%,reference_number.ilike.%$q%,customer_name_snapshot.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<SalesInvoice?> getById(String id) async {
    try {
      final row = await _client
          .from('sales_invoices')
          .select('''
id, invoice_number, reference_number, sales_order_id, customer_id,
customer_name_snapshot, customer_phone_snapshot, customer_address_snapshot,
customer_tax_number_snapshot, warehouse_id, status, subtotal, discount,
taxable_amount, tax_amount, grand_total, payment_method_id, payment_status,
delivery_method, credit_period_days, due_date, credit_reason,
created_by, approved_by, approved_at, rejected_by, rejected_at,
rejection_reason, created_at,
customers ( name ), warehouses ( name ),
payment_methods ( code, name, name_ar )
''')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return SalesInvoice.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>?> getRawById(String id) async {
    final row = await _client
        .from('sales_invoices')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<SalesInvoiceItem>> itemsOf(String invoiceId) async {
    try {
      final rows = (await _client
          .from('sales_invoice_items')
          .select()
          .eq('sales_invoice_id', invoiceId)
          .order('item_name')) as List;
      return rows
          .map((e) => SalesInvoiceItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> paymentMethods() async {
    final rows = (await _client
        .from('payment_methods')
        .select()
        .eq('is_active', true)
        .order('code')) as List;
    return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  }

  /// Creates DRAFT header + items (direct RLS writes; no stock effect).
  Future<String> createDraft({
    String? customerId,
    String? customerName,
    String? warehouseId,
    String? paymentMethodId,
    String? reference,
    String delivery = 'OFFICE_PICKUP',
    String? creditReason,
    required List<SalesItemInput> items,
  }) async {
    try {
      final header = await _client
          .from('sales_invoices')
          .insert({
            'customer_id': customerId,
            'customer_name_snapshot': customerName,
            'warehouse_id': warehouseId,
            'payment_method_id': paymentMethodId,
            'reference_number':
                reference?.trim().isEmpty == true ? null : reference?.trim(),
            'delivery_method': delivery,
            'credit_reason': creditReason?.trim().isEmpty == true
                ? null
                : creditReason?.trim(),
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (header as Map)['id'] as String;
      if (items.isNotEmpty) {
        await _client.from('sales_invoice_items').insert(
            [for (final it in items) it.toMap(id)]);
      }
      await _client.rpc('recalc_sales_invoice', params: {'p_invoice': id});
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> addItems(String invoiceId, List<SalesItemInput> items) async {
    try {
      await _client.from('sales_invoice_items').insert(
          [for (final it in items) it.toMap(invoiceId)]);
      await _client.rpc('recalc_sales_invoice', params: {'p_invoice': invoiceId});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// تعديل سطر في مسودة (سعر/كمية/ضريبة/خصم).
  /// يحدث sales_invoice_items فقط + recalc للإجماليات،
  /// ولا يمس products.sale_price ولا warehouse_stock.
  Future<void> updateItem({
    required String itemId,
    required String invoiceId,
    double? quantity,
    double? unitPrice,
    double? taxRate,
    double? discount,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (quantity != null) payload['quantity'] = quantity;
      if (unitPrice != null) payload['unit_price'] = unitPrice;
      if (taxRate != null) payload['tax_rate'] = taxRate;
      if (discount != null) payload['discount'] = discount;
      if (payload.isEmpty) return;
      await _client
          .from('sales_invoice_items')
          .update(payload)
          .eq('id', itemId);
      await _client.rpc('recalc_sales_invoice',
          params: {'p_invoice': invoiceId});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> removeItem(String itemId, String invoiceId) async {
    try {
      await _client.from('sales_invoice_items').delete().eq('id', itemId);
      await _client.rpc('recalc_sales_invoice', params: {'p_invoice': invoiceId});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// تعديل تكلفة صنف خاص في فاتورة معتمدة (سعر الشراء).
  /// يحدث unit_cost فقط — لا يغير الإجماليات، لكن يصحح الربح
  /// (البيع − الشراء) والتقارير والمرتجعات اللاحقة.
  Future<void> updateItemCost({
    required String itemId,
    required double unitCost,
  }) async {
    try {
      if (unitCost < 0) throw const ValidationFailure('التكلفة لا تكون سالبة');
      await _client
          .from('sales_invoice_items')
          .update({'unit_cost': unitCost})
          .eq('id', itemId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// ربط سطر صنف خاص بطلب التصنيع المنشأ عنه (بدون تغيير الإجماليات).
  Future<void> setCustomizedItem(String itemId, String czId) async {
    try {
      await _client
          .from('sales_invoice_items')
          .update({'customized_item_id': czId})
          .eq('id', itemId);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submit(String id) async {
    try {
      await _client.rpc('submit_sales_invoice', params: {'p_invoice': id});
    } catch (e, st) {
      debugPrint('sales.submit_sales_invoice RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<void> approve(String id) async {
    try {
      await _client.rpc('approve_sales_invoice', params: {'p_invoice': id});
    } catch (e, st) {
      debugPrint('sales.approve_sales_invoice RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<void> reject(String id, String reason) async {
    try {
      await _client.rpc('reject_sales_invoice',
          params: {'p_invoice': id, 'p_reason': reason});
    } catch (e, st) {
      debugPrint('sales.reject_sales_invoice RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// خصم مباشر لمخزون فاتورة معتمدة (نسخة الجهاز فقط — استلام فوري).
  /// في السحابة غير مدعومة (الخصم يتم عبر الشحن).
  Future<void> fulfill(String id) async {
    try {
      await _client.rpc('fulfill_sales_invoice', params: {'p_invoice': id});
    } catch (e, st) {
      debugPrint('sales.fulfill_sales_invoice RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إنشاء + إرسال + اعتماد + خصم مباشر في خطوة واحدة
  /// (نسخة الجهاز — مستخدم واحد، بدون مركز موافقات).
  /// للشحن (SHIPPING): الاعتماد يحجز المخزون والشحنة
  /// تُنشأ وتُشحن خارج هذه الدالة (نفس التوقيع يرجع المعرف).
  Future<String> createAndApprove({
    String? customerId,
    String? customerName,
    String? warehouseId,
    String? paymentMethodId,
    String? reference,
    String delivery = 'OFFICE_PICKUP',
    String? creditReason,
    required List<SalesItemInput> items,
  }) async {
    final id = await createDraft(
      customerId: customerId,
      customerName: customerName,
      warehouseId: warehouseId,
      paymentMethodId: paymentMethodId,
      reference: reference,
      delivery: delivery,
      creditReason: creditReason,
      items: items,
    );
    await submit(id);
    await approve(id);
    if (delivery != 'SHIPPING') {
      await fulfill(id);
    }
    return id;
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return SalesRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return SalesRepository(ref.watch(supabaseClientProvider));
});
