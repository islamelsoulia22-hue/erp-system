// النسخة اللوكال: دخول + أصناف على قاعدة مؤقتة لكل
// اختبار (ملف مستقل — لا مشاركة بين الاختبارات).
// التشغيل: flutter test test/local_auth_products_test.dart
import 'dart:io';

import 'package:accounting_system/core/local/local_auth.dart';
import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_products.dart';
import 'package:accounting_system/core/local/password_hash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openSeeded() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_local_test_');
  final db = await databaseFactoryFfi.openDatabase(p.join(dir.path, 't.db'));
  for (final s in LocalDatabase.schemaV1) {
    await db.execute(s);
  }
  for (final s in LocalDatabase.migrationV1toV2) {
    await db.execute(s);
  }
  const email = 'admin@local';
  final salt = PasswordHash.generateSalt();
  await db.insert('users', {
    'id': 'u1',
    'full_name': 'مدير',
    'email': email,
    'password_salt': salt,
    'password_hash': PasswordHash.hash('admin123', salt),
    'is_active': 1,
    'created_at': '2026-01-01',
  });
  return db;
}

void main() {
  test('v2 migration adds auth columns + session table', () async {
    final db = await _openSeeded();
    try {
      final cols = await db.rawQuery('PRAGMA table_info(users)');
      final names = {for (final c in cols) c['name'] as String};
      expect(names, containsAll(['password_hash', 'password_salt']));
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='local_session'",
      );
      expect(tables.length, 1);
    } finally {
      await db.close();
    }
  });

  test('login/logout/session round-trip', () async {
    final db = await _openSeeded();
    try {
      final repo = LocalAuthRepository(() async => db);
      expect(await repo.currentUser(), isNull);
      final user = await repo.login(
        email: 'ADMIN@local ',
        password: 'admin123',
      );
      expect(user.fullName, 'مدير');
      expect((await repo.currentUser())?.id, 'u1');
      // باسورد غلط يترفض.
      await repo.logout();
      expect(await repo.currentUser(), isNull);
      await expectLater(
        () => repo.login(email: 'admin@local', password: 'غلط'),
        throwsA(isA<LocalAuthFailure>()),
      );
    } finally {
      await db.close();
    }
  });

  test('products crud + search + paging', () async {
    final db = await _openSeeded();
    try {
      final repo = LocalProductsRepository(() async => db);
      final id = await repo.create(
        name: 'سكر',
        sku: 'SG1',
        purchasePrice: 10,
        salePrice: 15,
      );
      await repo.create(name: 'سجاير');
      // الاسم الفاضي مرفوض.
      await expectLater(
        () => repo.create(name: '  '),
        throwsA(isA<LocalDataFailure>()),
      );
      var p = await repo.page();
      expect(p.total, 2);
      p = await repo.page(query: 'سك');
      expect(p.total, 1);
      expect(p.items.first.id, id);
      final one = await repo.getById(id);
      expect(one?.salePrice, 15);
      await repo.setActive(id, false);
      p = await repo.page();
      expect(p.total, 1);
      p = await repo.page(onlyActive: false);
      expect(p.total, 2);
      await repo.remove(id);
      expect(await repo.getById(id), isNull);
    } finally {
      await db.close();
    }
  });

  test('password hash verifies and rejects', () {
    final salt = PasswordHash.generateSalt();
    final h = PasswordHash.hash('secret', salt);
    expect(PasswordHash.verify('secret', salt, h), isTrue);
    expect(PasswordHash.verify('other', salt, h), isFalse);
  });
}
