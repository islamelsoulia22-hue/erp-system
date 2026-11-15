import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_mode.dart';
import '../../../core/errors/failures.dart';
import '../../../core/local/local_database.dart';
import '../../../core/local/local_query.dart';
import '../../../core/network/supabase_client.dart';

/// مستودع الصيانة والإصلاح: مسح كل بيانات الشغل مع الحفاظ على المستخدمين.
///
/// ينده دالة السيرفر `reset_all_data_keep_users` (مدير فقط users.manage).
/// ما يُمسح: فواتير/طلبات/مدفوعات/شحنات/مرتجعات/مشتريات/تصنيع/مخزون/
/// عملاء/موردون/منتجات/مخازن/مصروفات/مرفقات/موافقات/سجلات/إشعارات.
/// ما يُحفظ: المستخدمون والأدوار والصلاحيات + بيانات التأسيس
/// (طرق الدفع/الوحدات/تصنيفات المنتجات والمصروفات/الإعدادات).
class MaintenanceRepository {
  final dynamic _client;
  MaintenanceRepository(this._client);

  Future<void> resetAllData() async {
    try {
      await _client.rpc('reset_all_data_keep_users');
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  // نسخة الجهاز: نفس الكلاس على SQLite عبر المحول — نفس الشاشات.
  if (resolveBackendMode() == BackendMode.local) {
    return MaintenanceRepository(
      LocalDbClient(() => LocalDatabase.instance.db),
    );
  }
  return MaintenanceRepository(ref.watch(supabaseClientProvider));
});
