import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../domain/expense.dart';

const _expSelect = '''
id, expense_number, category_id, title, amount, expense_date,
payment_method_id, party_name, reference_number, warehouse_id,
notes, status, payment_status, created_by, rejection_reason,
group_id, created_at,
expense_categories ( name, name_ar ),
warehouses ( name ),
payment_methods ( code, name, name_ar )
''';

class ExpensesRepository {
  final dynamic _client;
  ExpensesRepository(this._client);

  // ---------- Categories ----------
  Future<List<ExpenseCategory>> categories(
      {bool onlyActive = true}) async {
    try {
      var req =
          _client.from('expense_categories').select();
      if (onlyActive) req = req.eq('is_active', true);
      req = req.order('name_ar');
      final rows = (await req) as List;
      return rows
          .map((e) => ExpenseCategory.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<ExpenseCategory> createCategory(
      {required String name, String? nameAr}) async {
    try {
      final ts =
          DateTime.now().millisecondsSinceEpoch.toString();
      final row = await _client
          .from('expense_categories')
          .insert({
            'code': 'EXC-${ts.substring(ts.length - 6)}',
            'name': name.trim(),
            'name_ar': nameAr?.trim().isEmpty == true
                ? null
                : nameAr?.trim(),
            'is_active': true,
            'created_by': _client.auth.currentUser?.id,
          })
          .select()
          .single();
      return ExpenseCategory.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------- Expenses ----------
  Future<List<Expense>> list({
    String query = '',
    String? status,
    String? categoryId,
    DateTime? from,
    DateTime? to,
    int page = 0,
    int pageSize = AppConstants.pageSize,
  }) async {
    try {
      var req = _client.from('expenses').select(_expSelect);
      if (status != null && status.isNotEmpty) {
        if (status == 'PAID') {
          req = req.eq('payment_status', 'PAID');
        } else if (status == 'APPROVED_UNPAID') {
          req = req
              .eq('status', 'APPROVED')
              .eq('payment_status', 'UNPAID');
        } else {
          req = req.eq('status', status);
        }
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        req = req.eq('category_id', categoryId);
      }
      if (from != null) {
        req = req.gte('expense_date',
            DateTime(from.year, from.month, from.day)
                .toIso8601String()
                .substring(0, 10));
      }
      if (to != null) {
        req = req.lte('expense_date',
            DateTime(to.year, to.month, to.day)
                .toIso8601String()
                .substring(0, 10));
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'expense_number.ilike.%$q%,title.ilike.%$q%,party_name.ilike.%$q%');
      }
      req = req
          .order('expense_date', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1);
      final rows = (await req) as List;
      return rows
          .map((e) => Expense.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد المصروفات المطابقة (لترقيم الصفحات — نفس فلاتر [list]).
  Future<int> count({
    String query = '',
    String? status,
    String? categoryId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      var req = _client.from('expenses').select('id');
      if (status != null && status.isNotEmpty) {
        if (status == 'PAID') {
          req = req.eq('payment_status', 'PAID');
        } else if (status == 'APPROVED_UNPAID') {
          req = req
              .eq('status', 'APPROVED')
              .eq('payment_status', 'UNPAID');
        } else {
          req = req.eq('status', status);
        }
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        req = req.eq('category_id', categoryId);
      }
      if (from != null) {
        req = req.gte('expense_date',
            DateTime(from.year, from.month, from.day)
                .toIso8601String()
                .substring(0, 10));
      }
      if (to != null) {
        req = req.lte('expense_date',
            DateTime(to.year, to.month, to.day)
                .toIso8601String()
                .substring(0, 10));
      }
      final q = query.trim();
      if (q.isNotEmpty) {
        req = req.or(
            'expense_number.ilike.%$q%,title.ilike.%$q%,party_name.ilike.%$q%');
      }
      final res = await req.count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Expense?> getById(String id) async {
    try {
      final row = await _client
          .from('expenses')
          .select(_expSelect)
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Expense.fromMap(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> create(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('expenses')
          .insert({
            ...data,
            'status': 'DRAFT',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      return (row as Map)['id'] as String;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> submit(String id) =>
      _rpc('submit_expense', {'p_id': id});
  Future<void> approve(String id) =>
      _rpc('approve_expense', {'p_id': id});
  Future<void> reject(String id, String reason) =>
      _rpc('reject_expense', {'p_id': id, 'p_reason': reason});
  Future<void> pay(String id,
          {String? methodId, String? reference}) =>
      _rpc('pay_expense', {
        'p_id': id,
        'p_method_id': methodId,
        'p_reference': reference,
      });

  /// إجمالي المصروفات المدفوعة في مدى (للأرباح — المرحلة 3).
  Future<double> paidTotal({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final rows = (await _client
          .from('expenses')
          .select('amount')
          .eq('payment_status', 'PAID')
          .gte('expense_date',
              DateTime(from.year, from.month, from.day)
                  .toIso8601String()
                  .substring(0, 10))
          .lt('expense_date',
              DateTime(to.year, to.month, to.day)
                  .add(const Duration(days: 1))
                  .toIso8601String()
                  .substring(0, 10))) as List;
      var t = 0.0;
      for (final r in rows) {
        final v = (r as Map)['amount'];
        t += v is num
            ? v.toDouble()
            : double.tryParse(v?.toString() ?? '') ?? 0;
      }
      return t;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } catch (e, st) {
      debugPrint('expenses.$fn RAW error: $e (${e.runtimeType})\n$st');
      throw mapSupabaseError(e);
    }
  }

  // ---------- Recurring templates (phase 2) ----------
  Future<List<Map<String, dynamic>>> templates() async {
    try {
      final rows = (await _client
          .from('expenses')
          .select(_expSelect)
          .eq('is_recurring', true)
          .order('created_at', ascending: false)
          .range(0, 199)) as List;
      return [
        for (final r in rows) Map<String, dynamic>.from(r as Map)
      ];
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createTemplate(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('expenses')
          .insert({
            ...data,
            'is_recurring': true,
            'status': 'APPROVED',
            'payment_status': 'UNPAID',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      return (row as Map)['id'] as String;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> updateTemplate(
      String id, Map<String, dynamic> data) async {
    try {
      await _client
          .from('expenses')
          .update(data)
          .eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<String> createInstance(Map<String, dynamic> data) async {
    try {
      final row = await _client
          .from('expenses')
          .insert({
            ...data,
            'is_recurring': false,
            'status': 'APPROVED',
            'payment_status': 'UNPAID',
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id')
          .single();
      return (row as Map)['id'] as String;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ---------- Installments (phase 2) ----------
  Future<List<Expense>> installments() async {
    try {
      final rows = (await _client
          .from('expenses')
          .select(_expSelect)
          .not('group_id', 'is', null)
          .order('expense_date')
          .range(0, 999)) as List;
      return rows
          .map((e) => Expense.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createInstallment(Map<String, dynamic> data) async {
    try {
      await _client.from('expenses').insert({
        ...data,
        'is_recurring': false,
        'status': 'APPROVED',
        'payment_status': 'UNPAID',
        'created_by': _client.auth.currentUser?.id,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final expensesRepositoryProvider =
    Provider<ExpensesRepository>((ref) {
  // نسخة الجهاز: الوحدة مستبعدة من القوائم — التحويل للأمان فقط.
  if (resolveBackendMode() == BackendMode.local) {
    return ExpensesRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return ExpensesRepository(ref.watch(supabaseClientProvider));
});
