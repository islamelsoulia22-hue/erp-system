import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';

/// سجل بيع السيريالات (الطابعات والأجهزة بسيريال).
class SerialSale {
  final String serial;
  final String? productId;
  final String? productName;
  final String? brand;
  final String? model;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? invoiceId;
  final String? invoiceNumber;
  final DateTime? soldAt;
  final double unitPrice;
  final double unitCost;

  const SerialSale({
    required this.serial,
    this.productId,
    this.productName,
    this.brand,
    this.model,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.invoiceId,
    this.invoiceNumber,
    this.soldAt,
    this.unitPrice = 0,
    this.unitCost = 0,
  });

  double get profit => unitPrice - unitCost;

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  factory SerialSale.fromMap(Map<String, dynamic> m) {
    return SerialSale(
      serial: (m['serial'] as String?) ?? '',
      productId: m['product_id'] as String?,
      productName: m['product_name'] as String?,
      brand: m['brand'] as String?,
      model: m['model'] as String?,
      customerId: m['customer_id'] as String?,
      customerName: m['customer_name'] as String?,
      customerPhone: m['customer_phone'] as String?,
      invoiceId: m['sales_invoice_id'] as String?,
      invoiceNumber: m['invoice_number'] as String?,
      soldAt: m['sold_at'] == null
          ? null
          : DateTime.tryParse(m['sold_at'].toString()),
      unitPrice: _n(m['unit_price']),
      unitCost: _n(m['unit_cost']),
    );
  }
}

class SerialsRepository {
  final dynamic _client;
  SerialsRepository(this._client);

  /// التحقق من السيريال: يرجع الملف الكامل أو null لو مش متباع.
  Future<SerialSale?> verify(String serial) async {
    try {
      final s = serial.trim();
      if (s.isEmpty) return null;
      final rows = (await _client.rpc('verify_serial',
          params: {'p_serial': s})) as List;
      if (rows.isEmpty) return null;
      return SerialSale.fromMap(
          Map<String, dynamic>.from(rows.first as Map));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// اقتراحات السيريالات أثناء الكتابة (للبحث السريع).
  Future<List<String>> suggest(String query, {int limit = 10}) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return [];
      final rows = (await _client
          .from('serial_sales')
          .select('serial')
          .ilike('serial', '%$q%')
          .order('sold_at', ascending: false)
          .limit(limit)) as List;
      return [
        for (final r in rows)
          ((r as Map)['serial'] as String?) ?? ''
      ].where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// لو السيريال مش متباع: هل هو في مخزون السيريالات (متباعش)؟
  /// يرجع {serial, product_id, product_name} أو null لو مجهول تماما.
  Future<Map<String, dynamic>?> stockLookup(String serial) async {
    try {
      final s = serial.trim();
      if (s.isEmpty) return null;
      final row = await _client
          .from('product_serials')
          .select('serial, product_id, products ( name )')
          .ilike('serial', s)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row as Map);
      final p = m['products'];
      return {
        'serial': m['serial'],
        'product_id': m['product_id'],
        'product_name':
            p is Map ? (p['name'] as String?) : null,
      };
    } catch (_) {
      return null;
    }
  }

  /// تسجيل بيع سيريال على سطر فاتورة معتمدة.
  Future<void> registerSale({
    required String itemId,
    required String serial,
    String? notes,
  }) async {
    try {
      await _client.rpc('register_serial_sale', params: {
        'p_item_id': itemId,
        'p_serial': serial.trim(),
        'p_notes': notes,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
  /// تسجيل بيع يدوي (مبيعات قديمة بدون فاتورة نظام).
  Future<void> registerManualSale({
    required String serial,
    String? productId,
    String? productName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    double unitPrice = 0,
    double unitCost = 0,
    DateTime? soldAt,
    String? notes,
  }) async {
    try {
      final s = serial.trim();
      if (s.isEmpty) throw const ValidationFailure('اكتب السيريال.');
      await _client.from('serial_sales').insert({
        'serial': s,
        'product_id': productId,
        'product_name_snapshot': productName,
        'customer_id': customerId,
        'customer_name_snapshot': customerName,
        'customer_phone_snapshot': customerPhone,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'sold_at': (soldAt ?? DateTime.now()).toIso8601String(),
        'notes': notes,
        'created_by': _client.auth.currentUser?.id,
      });
      // لو كان في المخزون: خرج (اتباع).
      try {
        await _client
            .from('product_serials')
            .delete()
            .ilike('serial', s);
      } catch (_) {}
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final serialsRepositoryProvider =
    Provider<SerialsRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return SerialsRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return SerialsRepository(ref.watch(supabaseClientProvider));
});
