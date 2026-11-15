import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';

/// تنبيه مخزون (حد أدنى / نفاذ).
class StockAlert {
  final String id;
  final String? productId;
  final String productName;
  final double minimumStock;
  final String? supplierId;
  final String? warehouseId;
  final String warehouseName;
  final String level;
  final String status;
  final double availableAtAlert;
  final DateTime createdAt;

  const StockAlert({
    required this.id,
    this.productId,
    required this.productName,
    this.minimumStock = 0,
    this.supplierId,
    this.warehouseId,
    required this.warehouseName,
    required this.level,
    required this.status,
    required this.availableAtAlert,
    required this.createdAt,
  });

  bool get isOut => level == 'OUT_OF_STOCK';
  bool get isNew => status == 'NEW';

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory StockAlert.fromMap(Map<String, dynamic> m) {
    final p = m['products'];
    final w = m['warehouses'];
    return StockAlert(
      id: m['id'] as String,
      productId: m['product_id'] as String?,
      productName: p is Map
          ? ((p['name'] as String?) ?? '')
          : '',
      minimumStock:
          p is Map ? _n(p['minimum_stock']) : 0,
      supplierId: p is Map
          ? p['supplier_id'] as String?
          : m['supplier_id'] as String?,
      warehouseId: m['warehouse_id'] as String?,
      warehouseName: w is Map
          ? ((w['name'] as String?) ?? '')
          : '',
      level: (m['level'] as String?) ?? 'MINIMUM',
      status: (m['status'] as String?) ?? 'NEW',
      availableAtAlert: _n(m['available_qty']),
      createdAt: DateTime.tryParse(
              m['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class StockAlertsRepository {
  final dynamic _client;
  StockAlertsRepository(this._client);

  Future<List<StockAlert>> list({String? status}) async {
    try {
      var req = _client.from('stock_alerts').select(
          '*, products ( name, minimum_stock, supplier_id ), warehouses ( name )');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final rows = (await req
          .order('created_at', ascending: false)
          .range(0, 99)) as List;
      return rows
          .map((e) => StockAlert.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<int> newCount() async {
    try {
      final rows = (await _client
          .from('stock_alerts')
          .select('id')
          .eq('status', 'NEW')) as List;
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// إقرار المدير: "عارف تمام".
  Future<void> acknowledge(String id) async {
    try {
      await _client.from('stock_alerts').update({
        'status': 'ACK',
        'ack_by': _client.auth.currentUser?.id,
        'ack_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final stockAlertsRepositoryProvider =
    Provider<StockAlertsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return StockAlertsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return StockAlertsRepository(
      ref.watch(supabaseClientProvider));
});

final stockAlertsProvider = FutureProvider.autoDispose
    .family<List<StockAlert>, String?>((ref, status) {
  return ref
      .watch(stockAlertsRepositoryProvider)
      .list(status: status);
});

final stockAlertsNewCountProvider =
    FutureProvider.autoDispose<int>((ref) {
  return ref
      .watch(stockAlertsRepositoryProvider)
      .newCount();
});
