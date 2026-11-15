import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/widgets/app_pagination.dart';
import '../domain/shipping.dart';

class ShippingRepository {
  final dynamic _client;
  ShippingRepository(this._client);

  Future<List<Shipment>> list({int page = 0, int pageSize = AppConstants.pageSize}) async {
    try {
      final rows = (await _client
          .from('shipments')
          .select('*, sales_invoices ( invoice_number )')
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) =>
              Shipment.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد الشحنات (لترقيم الصفحات).
  Future<int> count() async {
    try {
      final res = await _client.from('shipments').select('id').count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Shipment?> getById(String id) async {
    try {
      final row = await _client
          .from('shipments')
          .select('*, sales_invoices ( invoice_number )')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Shipment.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>?> getRaw(String id) async {
    final row = await _client
        .from('shipments')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<String> create(Map<String, dynamic> data) async {
    try {
      // Shipping requires recipient info per spec.
      final delivery = data['delivery_method'];
      if (delivery == 'SHIPPING') {
        for (final k in [
          'recipient_name',
          'recipient_phone',
          'address'
        ]) {
          if ((data[k] as String?)?.trim().isEmpty != false) {
            throw const UnknownFailure();
          }
        }
      }
      final row = await _client
          .from('shipments')
          .insert({
            ...data,
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      return (row as Map)['id'] as String;
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw mapSupabaseError(e);
    }
  }

  Future<void> ship(String id) =>
      _rpc('ship_shipment', {'p_id': id});
  Future<void> deliver(String id) =>
      _rpc('deliver_shipment', {'p_id': id});

  Future<void> _rpc(String fn, Map<String, dynamic> p) async {
    try {
      await _client.rpc(fn, params: p);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final shippingRepositoryProvider = Provider<ShippingRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return ShippingRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ShippingRepository(ref.watch(supabaseClientProvider));
});

final shipmentsPageProvider = FutureProvider.autoDispose
      .family<PagedData<Shipment>, int>((ref, page) async {
  final repo = ref.watch(shippingRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(page: page, pageSize: ps),
    repo.count(),
  ]);
  return PagedData(res[0] as List<Shipment>, res[1] as int);
});

final shipmentDetailProvider =
    FutureProvider.autoDispose.family<Shipment?, String>((ref, id) {
  return ref.watch(shippingRepositoryProvider).getById(id);
});
