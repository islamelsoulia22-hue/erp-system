import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/purchases.dart';

const _poSelect = '''
id, order_number, supplier_id, warehouse_id, status,
grand_total, created_by, created_at, suppliers ( name )
''';

const _piSelect = '''
id, invoice_number, supplier_id, supplier_name_snapshot,
warehouse_id, status, payment_status, grand_total, created_by,
rejection_reason, created_at, suppliers ( name )
''';

class PurchasesRepository {
  final dynamic _client;
  PurchasesRepository(this._client);

  // ---------- Orders ----------
  Future<List<PurchaseOrder>> listOrders(
      {String query = '',
      String? status,
      int page = 0,
      int pageSize = AppConstants.pageSize}) async {
    try {
      var req =
          _client.from('purchase_orders').select(_poSelect);
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('order_number.ilike.%$q%,reference_number.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) =>
              PurchaseOrder.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد طلبات الشراء المطابقة (لترقيم الصفحات).
  Future<int> countOrders({String query = '', String? status}) async {
    try {
      var req = _client.from('purchase_orders').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('order_number.ilike.%$q%,reference_number.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<PurchaseOrder?> getOrder(String id) async {
    try {
      final row = await _client
          .from('purchase_orders')
          .select('''
id, order_number, reference_number, supplier_id, warehouse_id,
status, subtotal, discount, tax_amount, grand_total,
created_by, created_at, suppliers ( name ), warehouses ( name )
''')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return PurchaseOrder.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<PurchaseOrderItem>> orderItems(String orderId) async {
    try {
      final rows = (await _client
          .from('purchase_order_items')
          .select()
          .eq('purchase_order_id', orderId)
          .order('product_name')) as List;
      return rows
          .map((e) => PurchaseOrderItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createOrder({
    String? supplierId,
    String? warehouseId,
    String? reference,
    required List<POItemInput> items,
  }) async {
    try {
      final header = await _client
          .from('purchase_orders')
          .insert({
            'supplier_id': supplierId,
            'warehouse_id': warehouseId,
            'reference_number':
                reference?.trim().isEmpty == true ? null : reference?.trim(),
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (header as Map)['id'] as String;
      if (items.isNotEmpty) {
        await _client.from('purchase_order_items').insert(
            [for (final it in items) it.toMap(id)]);
      }
      await _client.rpc('recalc_purchase_order', params: {'p_order': id});
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submitOrder(String id) async {
    try {
      await _client.rpc('submit_purchase_order', params: {'p_order': id});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Partial receiving. lines: [{item_id, qty}]. ONLY path that adds stock.
  Future<void> receive(
      String orderId, List<Map<String, dynamic>> lines, String? notes) async {
    try {
      await _client.rpc('receive_purchase_order', params: {
        'p_order': orderId,
        'p_lines': lines,
        'p_notes': notes,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------- Invoices ----------
  Future<List<PurchaseInvoice>> listInvoices(
      {String query = '',
      String? status,
      int page = 0,
      String? supplierId,
      DateTime? from,
      DateTime? to,
      int pageSize = AppConstants.pageSize}) async {
    try {
      var req = _client
          .from('purchase_invoices')
          .select(_piSelect);
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      if (supplierId != null && supplierId.isNotEmpty) {
        req = req.eq('supplier_id', supplierId);
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
            'invoice_number.ilike.%$q%,reference_number.ilike.%$q%,supplier_name_snapshot.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) =>
              PurchaseInvoice.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد فواتير المشتريات المطابقة (لترقيم الصفحات).
  Future<int> countInvoices(
      {String query = '',
      String? status,
      String? supplierId,
      DateTime? from,
      DateTime? to}) async {
    try {
      var req = _client.from('purchase_invoices').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      if (supplierId != null && supplierId.isNotEmpty) {
        req = req.eq('supplier_id', supplierId);
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
            'invoice_number.ilike.%$q%,reference_number.ilike.%$q%,supplier_name_snapshot.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<PurchaseInvoice?> getInvoice(String id) async {
    try {
      final row = await _client
          .from('purchase_invoices')
          .select('''
id, invoice_number, reference_number, purchase_order_id, supplier_id,
supplier_name_snapshot, warehouse_id, status, payment_status,
subtotal, discount, taxable_amount, tax_amount, grand_total,
payment_method_id, created_by, rejection_reason, created_at,
suppliers ( name ), warehouses ( name ),
payment_methods ( code, name, name_ar )
''')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return PurchaseInvoice.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<PurchaseInvoiceItem>> invoiceItems(String invoiceId) async {
    try {
      final rows = (await _client
          .from('purchase_invoice_items')
          .select()
          .eq('purchase_invoice_id', invoiceId)
          .order('product_name_snapshot')) as List;
      return rows
          .map((e) => PurchaseInvoiceItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createInvoice({
    String? orderId,
    String? supplierId,
    // اسم المورد النقدي (يُستخدم كـ snapshot عند عدم اختيار مورد مسجل).
    String? supplierName,
    String? warehouseId,
    String? paymentMethodId,
    String? reference,
    required List<PIItemInput> items,
  }) async {
    try {
      final cashName = supplierName?.trim();
      final header = await _client
          .from('purchase_invoices')
          .insert({
            'purchase_order_id': orderId,
            'supplier_id': supplierId,
            'supplier_name_snapshot':
                cashName?.isEmpty != false ? null : cashName,
            'warehouse_id': warehouseId,
            'payment_method_id': paymentMethodId,
            'reference_number':
                reference?.trim().isEmpty == true ? null : reference?.trim(),
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (header as Map)['id'] as String;
      if (items.isNotEmpty) {
        await _client.from('purchase_invoice_items').insert(
            [for (final it in items) it.toMap(id)]);
      }
      await _client
          .rpc('recalc_purchase_invoice', params: {'p_invoice': id});
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submitInvoice(String id) => _rpc(
      'submit_purchase_invoice', {'p_invoice': id});
  Future<void> approveInvoice(String id) => _rpc(
      'approve_purchase_invoice', {'p_invoice': id});

  /// إنشاء + إرسال + اعتماد في خطوة واحدة
  /// (نسخة الجهاز — مستخدم واحد، بدون مركز موافقات).
  /// الاعتماد يزيد المخزون تلقائيا للفواتير المباشرة.
  Future<String> createAndApproveInvoice({
    String? orderId,
    String? supplierId,
    String? supplierName,
    String? warehouseId,
    String? paymentMethodId,
    String? reference,
    required List<PIItemInput> items,
  }) async {
    final id = await createInvoice(
      orderId: orderId,
      supplierId: supplierId,
      supplierName: supplierName,
      warehouseId: warehouseId,
      paymentMethodId: paymentMethodId,
      reference: reference,
      items: items,
    );
    await submitInvoice(id);
    await approveInvoice(id);
    return id;
  }
  Future<void> rejectInvoice(String id, String reason) => _rpc(
      'reject_purchase_invoice', {'p_invoice': id, 'p_reason': reason});

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } catch (e, st) {
      debugPrint('purchases.$fn RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> paymentMethods() async {
    try {
      final rows = (await _client
          .from('payment_methods')
          .select()
          .eq('is_active', true)
          .order('code')) as List;
      return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return PurchasesRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return PurchasesRepository(ref.watch(supabaseClientProvider));
});
