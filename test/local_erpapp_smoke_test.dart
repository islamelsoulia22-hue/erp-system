// دخاني: نسخة الجهاز (BACKEND=local) تقلع بنفس تطبيق السحابة
// (ErpApp) وتصل لشاشة الدخول — بدون Supabase وبدون SQLite
// (الـ providers كسولة: لا تلمس القاعدة قبل الدخول).
// التشغيل: flutter test --dart-define=BACKEND=local
//   test/local_erpapp_smoke_test.dart
import 'package:accounting_system/app.dart';
import 'package:accounting_system/core/backend/backend_mode.dart';
import 'package:accounting_system/core/widgets/app_nav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// بدون --dart-define=BACKEND=local تُتخطى اختبارات وضع اللوكال
// حتى يبقى flutter test العادي أخضر (تُشغَّل كاملة في CI مع الـ flag).
const _needsLocalFlag =
    String.fromEnvironment('BACKEND', defaultValue: 'supabase') !=
        'local';

void main() {
  test('backend mode is local', skip: _needsLocalFlag, () {
    expect(resolveBackendMode(), BackendMode.local);
  });

  testWidgets('local ErpApp boots to cloud login screen',
      skip: _needsLocalFlag, (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ErpApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // شاشة دخول السحابة نفسها (البريد + كلمة المرور + زرار دخول).
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('دخول'), findsWidgets);
  });

  test('excluded routes hidden in local', () {
    for (final r in [
      '/approvals',
      '/procurement',
      '/manufacturing',
      '/customized/new',
      '/manufacturing-orders/1',
      '/expenses',
      '/expenses/recurring',
    ]) {
      expect(isLocalExcludedRoute(r), isTrue, reason: r);
    }
    for (final r in [
      '/',
      '/sales',
      '/purchases',
      '/products',
      '/customers',
      '/suppliers',
      '/warehouses',
      '/inventory',
      '/payments',
      '/returns',
      '/reports',
      '/shipping',
      '/serials/verify',
      '/users',
      '/settings/returns',
      '/maintenance',
      '/notifications',
    ]) {
      expect(isLocalExcludedRoute(r), isFalse, reason: r);
    }
    // BottomNav بلا مستبعد.
    for (final i in BottomNav.items) {
      expect(isLocalExcludedRoute(i.route), isFalse);
    }
  });
}
