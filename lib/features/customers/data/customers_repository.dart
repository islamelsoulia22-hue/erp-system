import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/customer.dart';

class CustomersRepository {
  final dynamic _client;
  CustomersRepository(this._client);

  Future<List<Customer>> search({
    String query = '',
    int page = 0,
    int pageSize = AppConstants.pageSize,
    bool? onlyActive,
  }) async {
    try {
      var req = _client.from('customers').select();
      if (onlyActive == true) req = req.eq('is_active', true);
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'name.ilike.%$q%,phone.ilike.%$q%,customer_code.ilike.%$q%');
      }
      req = req
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) => Customer.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد العملاء المطابقين (لترقيم الصفحات — نفس فلاتر [search]).
  Future<int> count({String query = '', bool? onlyActive}) async {
    try {
      var req = _client.from('customers').select('id');
      if (onlyActive == true) req = req.eq('is_active', true);
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'name.ilike.%$q%,phone.ilike.%$q%,customer_code.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Customer?> getById(String id) async {
    try {
      final row = await _client
          .from('customers')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Customer.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Customer> create(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('customers')
          .insert({...data, 'created_by': _client.auth.currentUser?.id})
          .select()
          .single();
      await _audit('CREATE', 'CUSTOMER', (row as Map)['id'] as String,
          null, Map<String, dynamic>.from(row));
      return Customer.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Customer> update(String id, Map<String, dynamic> data) async {
    try {
      final before = await _client
          .from('customers')
          .select()
          .eq('id', id)
          .maybeSingle();
      final row = await _client
          .from('customers')
          .update(data)
          .eq('id', id)
          .select()
          .single();
      await _audit('UPDATE', 'CUSTOMER', id,
          before == null ? null : Map<String, dynamic>.from(before as Map),
          Map<String, dynamic>.from(row as Map));
      return Customer.fromMap(Map<String, dynamic>.from(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// حذف عميل (المدير فقط في UI؛ السيرفر يمنع لو عليه فواتير).
  Future<void> deleteCustomer(String id) async {
    try {
      await _client.from('customers').delete().eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<CustomerAddress>> addressesOf(String customerId) async {
    try {
      final rows = (await _client
          .from('customer_addresses')
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false)
          .order('created_at')) as List;
      return rows
          .map((e) =>
              CustomerAddress.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> upsertAddress(Map<String, dynamic> data) async {
    try {
      // If setting default, unset others first (single default invariant).
      if (data['is_default'] == true && data['customer_id'] != null) {
        await _client
            .from('customer_addresses')
            .update({'is_default': false})
            .eq('customer_id', data['customer_id'] as String);
      }
      if (data['id'] != null) {
        await _client
            .from('customer_addresses')
            .update(data)
            .eq('id', data['id'] as String);
      } else {
        await _client.from('customer_addresses').insert(data);
      }
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> removeAddress(String id) async {
    try {
      await _client.from('customer_addresses').delete().eq('id', id);
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

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return CustomersRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return CustomersRepository(ref.watch(supabaseClientProvider));
});
