import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/widgets/app_pagination.dart';
import '../domain/shortage.dart';

const _shortageSelect = '''
id, product_id, warehouse_id, supplier_id, required_qty,
status, source_type, source_id, notes, created_by, created_at,
products ( name ), warehouses ( name ), suppliers ( name )
''';

class ShortagesRepository {
  final dynamic _client;
  ShortagesRepository(this._client);

  Future<List<Shortage>> list(
      {String? status, int page = 0, int pageSize = 20}) async {
    try {
      var req = _client.from('shortages').select(_shortageSelect);
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) =>
              Shortage.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد النواقص بالحالة (لترقيم الصفحات — نفس فلتر [list]).
  Future<int> count({String? status}) async {
    try {
      var req = _client.from('shortages').select('id');
      if (status != null && status.isNotEmpty) {
        req = req.eq('status', status);
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<int> pendingCount() async {
    try {
      final rows = (await _client
          .from('shortages')
          .select('id')
          .eq('status', 'PENDING')) as List;
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// تسجيل نقص: لو فيه طلب PENDING لنفس الصنف + المخزن بيزود عليه،
  /// غير كده بينشئ طلب جديد. بيرجع true لو اتسجل جديد.
  Future<bool> record({
    required String productId,
    required String warehouseId,
    String? supplierId,
    required double requiredQty,
    String? sourceType,
    String? sourceId,
  }) async {
    try {
      if (requiredQty <= 0) return false;
      final existing = await _client
          .from('shortages')
          .select('id, required_qty')
          .eq('product_id', productId)
          .eq('warehouse_id', warehouseId)
          .eq('status', 'PENDING')
          .maybeSingle();
      if (existing != null) {
        final m = Map<String, dynamic>.from(existing as Map);
        final cur = m['required_qty'] is num
            ? (m['required_qty'] as num).toDouble()
            : double.tryParse(
                    m['required_qty']?.toString() ?? '') ??
                0;
        await _client.from('shortages').update({
          'required_qty': cur + requiredQty,
          'supplier_id': supplierId,
          'source_type': sourceType,
          'source_id': sourceId,
        }).eq('id', m['id']);
        return false;
      }
      await _client.from('shortages').insert({
        'product_id': productId,
        'warehouse_id': warehouseId,
        'supplier_id': supplierId,
        'required_qty': requiredQty,
        'status': 'PENDING',
        'source_type': sourceType,
        'source_id': sourceId,
        'created_by': _client.auth.currentUser?.id,
      });
      return true;
    } catch (e, st) {
      debugPrint(
          'shortages.record RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  Future<void> setStatus(String id, String status) async {
    try {
      await _client
          .from('shortages')
          .update({'status': status})
          .eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final shortagesRepositoryProvider =
    Provider<ShortagesRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return ShortagesRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ShortagesRepository(ref.watch(supabaseClientProvider));
});

final shortagesPageProvider = FutureProvider.autoDispose
    .family<PagedData<Shortage>, ({String? status, int page})>(
        (ref, args) async {
  final repo = ref.watch(shortagesRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(status: args.status, page: args.page, pageSize: ps),
    repo.count(status: args.status),
  ]);
  return PagedData(res[0] as List<Shortage>, res[1] as int);
});

final shortagesPendingCountProvider =
    FutureProvider.autoDispose<int>((ref) {
  return ref.watch(shortagesRepositoryProvider).pendingCount();
});
