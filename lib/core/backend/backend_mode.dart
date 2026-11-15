import 'package:flutter_riverpod/flutter_riverpod.dart';

/// وضع تشغيل التطبيق: نسخة السحابة (سوبابيز) أو نسخة
/// الجهاز (SQLite على الجهاز — بدون سيرفر).
///
/// الاختيار **وقت البناء/التشغيل** (نسختان منفصلتان)،
/// وليس زرار داخل التطبيق:
/// - سحابة (افتراضي): `flutter run` (سوبابيز من .env)
/// - لوكال: `flutter run --dart-define=BACKEND=local`
enum BackendMode { supabase, local }

/// يقرأ من `--dart-define=BACKEND=...` (قيمة ثابتة وقت البناء).
BackendMode resolveBackendMode() {
  const raw = String.fromEnvironment('BACKEND', defaultValue: 'supabase');
  return raw.trim().toLowerCase() == 'local'
      ? BackendMode.local
      : BackendMode.supabase;
}

/// وضع التشغيل الحالي — يُقرأ مرة واحدة عند الإقلاع.
final backendModeProvider = Provider<BackendMode>((ref) {
  return resolveBackendMode();
});

/// true في نسخة الجهاز (بدون سوبابيز).
bool isLocalBackend(WidgetRef ref) =>
    ref.watch(backendModeProvider) == BackendMode.local;

/// مسارات مستبعدة من نسخة الجهاز (المصاريف/الموافقات/التصنيع):
/// تُخفى من القوائم ويُحوَّل أي وصول مباشر للرئيسية.
const localExcludedRoutes = {
  '/approvals',
  '/procurement',
  '/manufacturing',
  '/customized',
  '/manufacturing-orders',
  '/expenses',
};

/// true لو المسار (أو أبواه) مستبعد محليا.
bool isLocalExcludedRoute(String path) {
  for (final r in localExcludedRoutes) {
    if (path == r || path.startsWith('$r/')) return true;
  }
  return false;
}
