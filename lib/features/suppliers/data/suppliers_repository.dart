import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/supplier.dart';

class SuppliersRepository {
  final dynamic _client;
  SuppliersRepository(this._client);

  Future<List<Supplier>> search({
    String query = '',
    int page = 0,
    int pageSize = AppConstants.pageSize,
    bool? onlyActive,
  }) async {
    try {
      var req = _client.from('suppliers').select();
      if (onlyActive == true) req = req.eq('is_active', true);
      final q = query.trim().replaceAll(RegExp(r'[,()]'), '');
      if (q.isNotEmpty) {
        req = req.or(
            'name.ilike.%$q%,phone.ilike.%$q%,supplier_code.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) => Supplier.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e, st) {
      debugPrint(
          'suppliers.search RAW error: $e | type=${e.runtimeType} | query="$query"\n$st');
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد الموردين المطابقين (لترقيم الصفحات — نفس فلاتر [search]).
  Future<int> count({String query = '', bool? onlyActive}) async {
    try {
      var req = _client.from('suppliers').select('id');
      if (onlyActive == true) req = req.eq('is_active', true);
      final q = query.trim().replaceAll(RegExp(r'[,()]'), '');
      if (q.isNotEmpty) {
        req = req.or(
            'name.ilike.%$q%,phone.ilike.%$q%,supplier_code.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Supplier?> getById(String id) async {
    try {
      final row = await _client
          .from('suppliers')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Supplier.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Supplier> create(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('suppliers')
          .insert({...data, 'created_by': _client.auth.currentUser?.id})
          .select()
          .single();
      await _audit('CREATE', 'SUPPLIER', (row as Map)['id'] as String,
          null, Map<String, dynamic>.from(row));
      return Supplier.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Supplier> update(String id, Map<String, dynamic> data) async {
    try {
      final before = await _client
          .from('suppliers')
          .select()
          .eq('id', id)
          .maybeSingle();
      final row = await _client
          .from('suppliers')
          .update(data)
          .eq('id', id)
          .select()
          .single();
      await _audit('UPDATE', 'SUPPLIER', id,
          before == null ? null : Map<String, dynamic>.from(before as Map),
          Map<String, dynamic>.from(row as Map));
      return Supplier.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف مورد (المدير فقط في UI؛ السيرفر يمنع لو عليه فواتير).
  Future<void> deleteSupplier(String id) async {
    try {
      await _client.from('suppliers').delete().eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _audit(String action, String entity, String id,
      Map<String, dynamic>? o, Map<String, dynamic>? n) async {
    try {
      await _client.from('audit_logs').insert({
        'user_id': _client.auth.currentUser?.id,
        'action': action,
        'entity_type': entity,
        'entity_id': id,
        'old_data': o,
        'new_data': n,
      });
    } catch (_) {}
  }
}

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return SuppliersRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return SuppliersRepository(ref.watch(supabaseClientProvider));
});
