import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/widgets/app_pagination.dart';
import '../domain/procurement.dart';

class ProcurementRepository {
  final dynamic _client;
  ProcurementRepository(this._client);

  Future<List<ProcurementRequest>> list(
      {String query = '',
      String? status,
      int page = 0,
      int pageSize = AppConstants.pageSize}) async {
    try {
      var req = _client
          .from('procurement_requests')
          .select('*, suppliers ( name )');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('request_number.ilike.%$q%,reason.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) => ProcurementRequest.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد طلبات التوريد المطابقة (لترقيم الصفحات).
  Future<int> count({String query = '', String? status}) async {
    try {
      var req = _client.from('procurement_requests').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('request_number.ilike.%$q%,reason.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<ProcurementRequest?> getById(String id) async {
    try {
      try {
        final row = await _client
            .from('procurement_requests')
            .select(
                '*, suppliers ( name ), warehouses ( name ), sales_invoices ( invoice_number, customer_name_snapshot, grand_total, status )')
            .eq('id', id)
            .maybeSingle();
        if (row == null) return null;
        return ProcurementRequest.fromMap(
            Map<String, dynamic>.from(row as Map));
      } catch (e) {
        // fallback لو عمود sales_invoice_id لسه متنفذش (قبل 0026).
        if (!_isMissingInvoiceLink(e)) rethrow;
        final row = await _client
            .from('procurement_requests')
            .select('*, suppliers ( name ), warehouses ( name )')
            .eq('id', id)
            .maybeSingle();
        if (row == null) return null;
        return ProcurementRequest.fromMap(
            Map<String, dynamic>.from(row as Map));
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// طلبات التوريد المرتبطة بفاتورة مبيعات (دورة الحجز) — الأحدث أولا.
  Future<List<ProcurementRequest>> listBySalesInvoice(
      String salesInvoiceId) async {
    try {
      final rows = (await _client
          .from('procurement_requests')
          .select('*, suppliers ( name ), warehouses ( name )')
          .eq('sales_invoice_id', salesInvoiceId)
          .order('created_at', ascending: false)) as List;
      return rows
          .map((e) => ProcurementRequest.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // قبل 0026: لا يوجد ربط — رجع فارغة بدل ما تكسر الشاشة.
      if (_isMissingInvoiceLink(e)) return [];
      throw mapSupabaseError(e);
    }
  }

  bool _isMissingInvoiceLink(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('sales_invoice_id') ||
        s.contains('sales_invoices') ||
        s.contains('pgrst200') ||
        s.contains('schema cache');
  }

  Future<List<ProcurementItem>> itemsOf(String id) async {
    try {
      final rows = (await _client
          .from('procurement_items')
          .select('*, products ( name )')
          .eq('procurement_id', id)) as List;
      return rows
          .map((e) => ProcurementItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> create({
    String? supplierId,
    String? salesOrderId,
    String? salesInvoiceId,
    required String warehouseId,
    String? reason,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final payload = {
        'supplier_id': supplierId,
        'sales_order_id': salesOrderId,
        'sales_invoice_id': salesInvoiceId,
        'warehouse_id': warehouseId,
        'reason': reason?.trim().isEmpty == true
            ? null
            : reason?.trim(),
        'status': 'DRAFT',
        'requested_by': _client.auth.currentUser?.id,
      };
      String id;
      try {
        final row = await _client
            .from('procurement_requests')
            .insert(payload)
            .select('id')
            .single();
        id = (row as Map)['id'] as String;
      } catch (e) {
        // fallback قبل 0026: شيل عمود الربط وأعد المحاولة.
        if (!_isMissingInvoiceLink(e)) rethrow;
        final clean = Map<String, dynamic>.from(payload)
          ..remove('sales_invoice_id');
        final row = await _client
            .from('procurement_requests')
            .insert(clean)
            .select('id')
            .single();
        id = (row as Map)['id'] as String;
      }
      await _client.from('procurement_items').insert([
        for (final it in items)
          {
            'procurement_id': id,
            'product_id': it['product_id'],
            'requested_quantity': it['qty'],
          }
      ]);
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submit(String id) =>
      _rpc('submit_procurement', {'p_id': id});
  Future<void> approve(String id) =>
      _rpc('approve_procurement', {'p_id': id});
  Future<void> reject(String id, String reason) =>
      _rpc('reject_procurement', {'p_id': id, 'p_reason': reason});

  /// تعديل المدير للطلب قبل الاستلام: كميات + مخزن (0026).
  Future<void> adjust(
    String id, {
    String? warehouseId,
    List<Map<String, dynamic>>? items,
  }) =>
      _rpc('adjust_procurement_request', {
        'p_id': id,
        'p_warehouse_id': warehouseId,
        'p_items': items,
      });

  Future<void> receive(
    String id,
    List<Map<String, dynamic>> lines,
    String? notes, {
    String? warehouseId,
  }) =>
      _rpc('receive_procurement', {
        'p_id': id,
        'p_lines': lines,
        'p_notes': notes,
        'p_warehouse_id': warehouseId,
      });

  /// إجمالي المدفوع (عربون/دفعات) على فاتورة مبيعات — يظهر للمدير
  /// إن الطلب حجز مدفوع منه مبلغ كذا.
  Future<double> invoicePaid(String salesInvoiceId) async {
    try {
      final rows = (await _client
          .from('payments')
          .select('amount')
          .eq('sales_invoice_id', salesInvoiceId)
          .eq('status', 'COMPLETED')) as List;
      var sum = 0.0;
      for (final r in rows) {
        final v = (Map<String, dynamic>.from(r as Map))['amount'];
        if (v is num) {
          sum += v.toDouble();
        } else {
          sum += double.tryParse(v.toString()) ?? 0;
        }
      }
      return sum;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// رقم المورد (للواتساب) — يرجع null لو مفيش.
  Future<String?> supplierPhone(String? supplierId) async {
    try {
      if (supplierId == null || supplierId.isEmpty) return null;
      final row = await _client
          .from('suppliers')
          .select('phone')
          .eq('id', supplierId)
          .maybeSingle();
      if (row == null) return null;
      final p = (row as Map)['phone'] as String?;
      if (p == null || p.trim().isEmpty) return null;
      return p.trim();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } catch (e, st) {
      debugPrint('procurement.$fn RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }
}

final procurementRepositoryProvider =
    Provider<ProcurementRepository>((ref) {
  // نسخة الجهاز: الوحدة مستبعدة من القوائم — التحويل للأمان فقط.
  if (resolveBackendMode() == BackendMode.local) {
    return ProcurementRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ProcurementRepository(ref.watch(supabaseClientProvider));
});

// ---------- Notifications (realtime) ----------
class NotificationsRepository {
  final dynamic _client;
  NotificationsRepository(this._client);

  Future<List<AppNotification>> list({int limit = 50}) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return [];
      final rows = (await _client
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit)) as List;
      return rows
          .map((e) => AppNotification.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _client.from('notifications').update(
          {'is_read': true, 'read_at': DateTime.now().toIso8601String()}).eq(
          'id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      await _client
          .from('notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String()
          })
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Realtime unread stream for the bell badge.
  /// نسخة الجهاز: بلا إشعارات (الجدول خارج النطاق) → صفر.
  Stream<int> unreadCount() {
    if (resolveBackendMode() == BackendMode.local) {
      return Stream.value(0);
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return Stream.value(0);
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .map((rows) =>
            rows.where((r) => (r as Map)['is_read'] == false).length);
  }
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  if (resolveBackendMode() == BackendMode.local) {
    return NotificationsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});

final notificationsListProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationsRepositoryProvider).list();
});

final unreadCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(notificationsRepositoryProvider).unreadCount();
});

final linkedSupplyProvider = FutureProvider.autoDispose
    .family<List<ProcurementRequest>, String>((ref, invoiceId) {
  return ref
      .watch(procurementRepositoryProvider)
      .listBySalesInvoice(invoiceId);
});

final procurementPageProvider = FutureProvider.autoDispose
      .family<PagedData<ProcurementRequest>, int>((ref, page) async {
  final repo = ref.watch(procurementRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(page: page, pageSize: ps),
    repo.count(),
  ]);
  return PagedData(res[0] as List<ProcurementRequest>, res[1] as int);
});

final procurementDetailProvider =
    FutureProvider.autoDispose.family<ProcurementRequest?, String>(
        (ref, id) {
  return ref.watch(procurementRepositoryProvider).getById(id);
});

final procurementItemsProvider =
    FutureProvider.autoDispose.family<List<ProcurementItem>, String>(
        (ref, id) {
  return ref.watch(procurementRepositoryProvider).itemsOf(id);
});
