import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/warehouse.dart';

const _stockSelect = '''
id, warehouse_id, product_id, quantity, reserved_quantity, available_quantity,
warehouses ( name ), products ( name, sku )
''';

class WarehousesRepository {
  final dynamic _client;
  WarehousesRepository(this._client);

  Future<List<Warehouse>> list({bool? onlyActive}) async {
    try {
      // الفلاتر قبل order: بعد order() بيرجع TransformBuilder ومفيهوش eq.
      var req = _client.from('warehouses').select();
      if (onlyActive == true) req = req.eq('is_active', true);
      req = req.order('created_at', ascending: false);
      final rows = (await req) as List;
      return rows
          .map((e) =>
              Warehouse.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'warehouses.list RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<Warehouse?> getById(String id) async {
    try {
      final row = await _client
          .from('warehouses')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Warehouse.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Warehouse> create(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('warehouses')
          .insert({...data, 'created_by': _client.auth.currentUser?.id})
          .select()
          .single();
      return Warehouse.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Warehouse> update(String id, Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('warehouses')
          .update(data)
          .eq('id', id)
          .select()
          .single();
      return Warehouse.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف مخزن (المدير فقط في UI؛ السيرفر يمنع لو عليه حركات/فواتير).
  Future<void> deleteWarehouse(String id) async {
    try {
      await _client.from('warehouses').delete().eq('id', id);
    } catch (e, st) {
      debugPrint(
          'warehouses.delete RAW error: $e | type=${e.runtimeType}\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// Stock lines for a warehouse (read-only query; never writes).
  Future<List<StockLine>> stockOf(String warehouseId) async {
    try {
      final rows = (await _client
          .from('warehouse_stock')
          .select(_stockSelect)
          .eq('warehouse_id', warehouseId)
          .order('quantity', ascending: false)) as List;
      return rows
          .map((e) =>
              StockLine.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Stock of ONE product across all warehouses (for product form / جرد).
  Future<List<StockLine>> stockOfProduct(String productId) async {
    try {
      final rows = (await _client
          .from('warehouse_stock')
          .select(_stockSelect)
          .eq('product_id', productId)
          .order('quantity', ascending: false)) as List;
      return rows
          .map((e) =>
              StockLine.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Global low-stock / overview with optional search.
  Future<List<StockLine>> overview(
      {String query = '', int page = 0, int pageSize = 50}) async {
    try {
      final rows = (await _client
          .from('warehouse_stock')
          .select(_stockSelect)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      final q = query.trim().toLowerCase();
      final all = rows
          .map((e) =>
              StockLine.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (q.isEmpty) return all;
      return all
          .where((s) =>
              s.productName.toLowerCase().contains(q) ||
              s.productSku.toLowerCase().contains(q) ||
              s.warehouseName.toLowerCase().contains(q))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<StockMovement>> movementsOf(
    String warehouseId, {
    int page = 0,
    int pageSize = 50,
  }) async {
    try {
      final rows = (await _client
          .from('stock_movements')
          .select()
          .eq('warehouse_id', warehouseId)
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) =>
              StockMovement.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// RPC-only writes. No direct table updates anywhere in the app.
  Future<void> adjust({
    required String warehouseId,
    required String productId,
    required double qtyChange,
    String? notes,
  }) async {
    try {
      await _client.rpc('create_stock_adjustment', params: {
        'p_warehouse_id': warehouseId,
        'p_product_id': productId,
        'p_qty_change': qtyChange,
        'p_notes': notes,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> transfer({
    required String fromWarehouse,
    required String toWarehouse,
    required String productId,
    required double quantity,
    String? notes,
  }) async {
    try {
      await _client.rpc('create_stock_transfer', params: {
        'p_from_warehouse': fromWarehouse,
        'p_to_warehouse': toWarehouse,
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_notes': notes,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final warehousesRepositoryProvider = Provider<WarehousesRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return WarehousesRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return WarehousesRepository(ref.watch(supabaseClientProvider));
});
