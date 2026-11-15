import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/manufacturing.dart';

class ManufacturingRepository {
  final dynamic _client;
  ManufacturingRepository(this._client);

  // ---------- Customized ----------
  Future<List<CustomizedItem>> listCustomized(
      {String query = '',
      String? status,
      int page = 0,
      int pageSize = AppConstants.pageSize}) async {
    try {
      var req = _client.from('customized_items').select();
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('name.ilike.%$q%,code.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) => CustomizedItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد الأصناف المخصصة المطابقة (لترقيم الصفحات).
  Future<int> countCustomized(
      {String query = '', String? status}) async {
    try {
      var req = _client.from('customized_items').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or('name.ilike.%$q%,code.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<CustomizedItem?> getCustomized(String id) async {
    try {
      final row = await _client
          .from('customized_items')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return CustomizedItem.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createCustomized(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('customized_items')
          .insert({...data, 'created_by': _client.auth.currentUser?.id})
          .select('id')
          .single();
      return (row as Map)['id'] as String;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submitCustomized(String id) =>
      _rpc('submit_customized_item', {'p_id': id});
  Future<void> approveCustomized(String id) =>
      _rpc('approve_customized_item', {'p_id': id});
  Future<void> rejectCustomized(String id, String reason) =>
      _rpc('reject_customized_item', {'p_id': id, 'p_reason': reason});

  // ---------- Manufacturing ----------
  Future<List<ManufacturingOrder>> listOrders({int page = 0, int pageSize = AppConstants.pageSize}) async {
    try {
      final rows = (await _client
          .from('manufacturing_orders')
          .select()
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) => ManufacturingOrder.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد أوامر التصنيع (لترقيم الصفحات).
  Future<int> countOrders() async {
    try {
      final res = await _client
          .from('manufacturing_orders')
          .select('id')
          .count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<ManufacturingOrder?> getOrder(String id) async {
    try {
      final row = await _client
          .from('manufacturing_orders')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return ManufacturingOrder.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<ManufacturingMaterial>> materialsOf(String orderId) async {
    try {
      final rows = (await _client
          .from('manufacturing_materials')
          .select('*, products ( name )')
          .eq('manufacturing_order_id', orderId)) as List;
      return rows
          .map((e) => ManufacturingMaterial.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createOrder({
    String? customizedId,
    String? warehouseId,
    String? finishedProductId,
    double? finishedQty,
    double quantity = 1,
    required List<Map<String, dynamic>> materials,
  }) async {
    try {
      final row = await _client
          .from('manufacturing_orders')
          .insert({
            'customized_item_id': customizedId,
            'warehouse_id': warehouseId,
            'finished_product_id': finishedProductId,
            'finished_quantity': finishedQty,
            'quantity': quantity,
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      final id = (row as Map)['id'] as String;
      if (materials.isNotEmpty) {
        await _client.from('manufacturing_materials').insert([
          for (final m in materials)
            {
              'manufacturing_order_id': id,
              'product_id': m['product_id'],
              'required_quantity': m['qty'],
            }
        ]);
      }
      return id;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> start(String id) =>
      _rpc('start_manufacturing', {'p_order': id});
  Future<void> complete(String id) =>
      _rpc('complete_manufacturing', {'p_order': id});

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } catch (e, st) {
      debugPrint('manufacturing.$fn RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }
}

final manufacturingRepositoryProvider =
    Provider<ManufacturingRepository>((ref) {
  // نسخة الجهاز: الوحدة مستبعدة من القوائم — التحويل للأمان فقط.
  if (resolveBackendMode() == BackendMode.local) {
    return ManufacturingRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ManufacturingRepository(ref.watch(supabaseClientProvider));
});
