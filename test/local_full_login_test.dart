// إثبات النهاية: نسخة الجهاز تدخل بنفس شاشة سحابة الدخول
// وتصل للداشبورد بنفس الشاشات (قاعدة SQLite حقيقية في مجلد مؤقت).
// ملاحظة تقنية: I/O الحقيقي (ملفات/sqflite) يعلق داخل FakeAsync
// الخاص بـ testWidgets — لذلك الإعداد في setUpAll (zone حقيقي)
// والتفاعل الذي يلمس القاعدة داخل tester.runAsync.
// التشغيل: flutter test --dart-define=BACKEND=local
//   test/local_full_login_test.dart
import 'dart:io';

import 'package:accounting_system/app.dart';
import 'package:accounting_system/core/backend/backend_mode.dart';
import 'package:accounting_system/core/local/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePaths with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final String dir;
  _FakePaths(this.dir);

  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getLibraryPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => dir;
  @override
  Future<String?> getExternalStoragePath() async => dir;
  @override
  Future<List<String>?> getExternalCachePaths() async => [dir];
  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [dir];
  @override
  Future<String?> getDownloadsPath() async => dir;
}

// بدون --dart-define=BACKEND=local يُتخطى الملف كله
// حتى يبقى flutter test العادي أخضر (يُشغَّل كاملا في CI مع الـ flag).
const _needsLocalFlag =
    String.fromEnvironment('BACKEND', defaultValue: 'supabase') !=
        'local';

void main() {
  setUpAll(() async {
    if (_needsLocalFlag) return;
    expect(resolveBackendMode(), BackendMode.local);
    final tmp = await Directory.systemTemp.createTemp('sanad_full_');
    PathProviderPlatform.instance = _FakePaths(tmp.path);
    await LocalDatabase.instance.ready();
  });

  tearDownAll(() async {
    if (_needsLocalFlag) return;
    await LocalDatabase.instance.close();
  });

  testWidgets('local: login with cloud screen → dashboard',
      skip: _needsLocalFlag, (tester) async {
    // شاشة ديسكتوب (قائمة جانبية ظاهرة).
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const ProviderScope(child: ErpApp()));
    await tester.pump();
    expect(find.text('كلمة المرور'), findsOneWidget);

    await tester.enterText(
        find.byType(TextFormField).at(0), 'admin@local');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'admin123');
    // الدخول يلمس SQLite → zone حقيقي.
    await tester.runAsync(() async {
      await tester.tap(find.text('دخول'));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
    });

    // داشبورد السحابة نفسه يعمل محليا.
    expect(find.text('لوحة التحكم'), findsWidgets);
    // المستبعد غير ظاهر في القائمة.
    expect(find.text('المصروفات'), findsNothing);
    expect(find.text('التصنيع'), findsNothing);
    expect(find.text('مركز الموافقات'), findsNothing);
    // والموجود ظاهر.
    expect(find.text('فواتير المبيعات'), findsWidgets);
  });
}
