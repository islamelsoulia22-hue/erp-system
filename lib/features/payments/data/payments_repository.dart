import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/widgets/app_pagination.dart';
import '../../shipping/domain/shipping.dart' show Payment, Balance;

class PaymentsRepository {
  final dynamic _client;
  PaymentsRepository(this._client);

  Future<List<Payment>> list({int page = 0, int pageSize = AppConstants.pageSize}) async {
    try {
      final rows = (await _client
          .from('payments')
          .select(
              '*, payment_methods ( code ), sales_invoices ( invoice_number, customer_name_snapshot ), purchase_invoices ( invoice_number, supplier_name_snapshot )')
          .order('created_at', ascending: false)
          .range(page * pageSize, (page + 1) * pageSize - 1)) as List;
      return rows
          .map((e) =>
              Payment.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// إجمالي عدد المدفوعات (لترقيم الصفحات).
  Future<int> count() async {
    try {
      final res = await _client.from('payments').select('id').count();
      return (res.count as int?) ?? 0;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> methods() async {
    final rows = (await _client
        .from('payment_methods')
        .select()
        .eq('is_active', true)
        .order('code')) as List;
    return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  }

  Future<void> pay({
    String? customerId,
    String? supplierId,
    String? salesInvoiceId,
    String? purchaseInvoiceId,
    String? methodId,
    required double amount,
    String? reference,
    String? notes,
  }) async {
    try {
      // Transfer methods should carry a reference (UX enforced, server optional).
      await _client.rpc('create_payment', params: {
        'p_customer_id': customerId,
        'p_supplier_id': supplierId,
        'p_sales_invoice_id': salesInvoiceId,
        'p_purchase_invoice_id': purchaseInvoiceId,
        'p_method_id': methodId,
        'p_amount': amount,
        'p_reference': reference,
        'p_notes': notes,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// مجموع المدفوع (COMPLETED) على فاتورة مشتريات —
  /// لحساب المتبقي في مستحقات المورد (الإجمالي − المدفوع).
  Future<double> purchaseInvoicePaid(String invoiceId) async {
    try {
      final rows = (await _client
          .from('payments')
          .select('amount')
          .eq('purchase_invoice_id', invoiceId)
          .eq('status', 'COMPLETED')) as List;
      var sum = 0.0;
      for (final r in rows) {
        final v = (r as Map)['amount'];
        sum += v is num
            ? v.toDouble()
            : double.tryParse(v?.toString() ?? '') ?? 0;
      }
      return sum;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Balance> customerBalance(String id) async {
    try {
      final rows = (await _client.rpc('customer_balance',
          params: {'p_customer': id})) as List;
      if (rows.isEmpty) {
        return const Balance(total: 0, paid: 0, outstanding: 0);
      }
      return Balance.fromMap(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Balance> supplierBalance(String id) async {
    try {
      final rows = (await _client.rpc('supplier_balance',
          params: {'p_supplier': id})) as List;
      if (rows.isEmpty) {
        return const Balance(total: 0, paid: 0, outstanding: 0);
      }
      return Balance.fromMap(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return PaymentsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return PaymentsRepository(ref.watch(supabaseClientProvider));
});

final paymentsPageProvider = FutureProvider.autoDispose
      .family<PagedData<Payment>, int>((ref, page) async {
  final repo = ref.watch(paymentsRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(page: page, pageSize: ps),
    repo.count(),
  ]);
  return PagedData(res[0] as List<Payment>, res[1] as int);
});
