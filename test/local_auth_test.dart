// إثبات المسار: AuthRepository (كود السحابة بدون تعديل)
// يعمل على SQLite عبر LocalDbClient — دخول/خروج/صلاحيات/أدوار/ملف.
// التشغيل: flutter test test/local_auth_test.dart
import 'dart:io';

import 'package:accounting_system/core/errors/failures.dart';
import 'package:accounting_system/core/local/local_database.dart';
import 'package:accounting_system/core/local/local_query.dart';
import 'package:accounting_system/core/local/password_hash.dart';
import 'package:accounting_system/features/auth/data/auth_repository.dart';
import 'package:accounting_system/features/users/data/users_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _open() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('sanad_auth_test_');
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dir.path, 't.db'),
    options: OpenDatabaseOptions(
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
    ),
  );
  for (final stmt in LocalDatabase.schemaV1) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV1toV2) {
    await db.execute(stmt);
  }
  for (final stmt in LocalDatabase.migrationV2toV3) {
    await db.execute(stmt);
  }
  await LocalDatabase.applyV4(db);
  await LocalDatabase.applyV5(db);
  return db;
}

Future<String> _seedAdmin(Database db) async {
  final salt = PasswordHash.generateSalt();
  final id = LocalDatabase.newId();
  await db.insert('users', {
    'id': id,
    'full_name': 'مدير',
    'email': 'admin@local',
    'password_salt': salt,
    'password_hash': PasswordHash.hash('admin123', salt),
    'is_active': 1,
    'created_at': DateTime.now().toIso8601String(),
  });
  // ربط ملف + دور (تختبر idempotency بإعادة التطبيق).
  await LocalDatabase.applyV5(db);
  return id;
}

void main() {
  test('v5 schema: tables + view + seeds', () async {
    final db = await _open();
    try {
      // view يعمل قبل أي بذر (صفوف فارغة لكن بدون خطأ).
      final before = await LocalDbClient(() async => db)
          .from('user_permissions')
          .select('permission_key');
      expect(before, isEmpty);
      await _seedAdmin(db);
      final perms =
          await db.rawQuery('SELECT COUNT(*) AS c FROM permissions');
      expect(perms.first['c'], 29);
      final roles = await db.rawQuery('SELECT COUNT(*) AS c FROM roles');
      expect(roles.first['c'], 3);
      // view بعد البذر: المدير يرى كل الصلاحيات عبر دوره.
      final after = await LocalDbClient(() async => db)
          .from('user_permissions')
          .select('permission_key');
      expect((after as List).length, 29);
      // إعادة التطبيق آمنة.
      await LocalDatabase.applyV5(db);
      final perms2 =
          await db.rawQuery('SELECT COUNT(*) AS c FROM permissions');
      expect(perms2.first['c'], 29);
    } finally {
      await db.close();
    }
  });

  test('auth full cycle on sqlite: login/perms/roles/profile/logout',
      () async {
    final db = await _open();
    try {
      LocalSession.clear();
      final adminId = await _seedAdmin(db);
      final client = LocalDbClient(() async => db);
      final repo = AuthRepository(client);

      // دخول ناجح.
      await repo.signIn(email: 'admin@local', password: 'admin123');
      expect(repo.currentUser?.id, adminId);
      expect(repo.currentUser?.email, 'admin@local');
      expect(LocalSession.currentUserId, adminId);

      // صلاحيات المدير = الكل (29) بما فيها الإضافات المتأخرة.
      final perms = await repo.loadMyPermissions();
      expect(perms.length, 29);
      expect(perms.contains('users.manage'), isTrue);
      expect(perms.contains('serials.verify'), isTrue);
      expect(perms.contains('expenses.view'), isTrue);

      // الدور + الملف.
      final roles = await repo.loadMyRoles();
      expect(roles, {'company_manager'});
      final profile = await repo.loadMyProfile();
      expect(profile?['email'], 'admin@local');
      expect(profile?['is_active'], isTrue);

      // تدقيق الدخول اتكتب.
      final audits = await db.query(
        'audit_logs',
        where: 'action = ?',
        whereArgs: ['LOGIN'],
      );
      expect(audits.isNotEmpty, isTrue);

      // خروج يمسح الجلسة.
      await repo.signOut();
      expect(repo.currentUser, isNull);
      expect(LocalSession.currentUserId, isNull);

      // باسورد غلط / إيميل مجهول → نفس رسالة السحابة.
      var bad = false;
      try {
        await repo.signIn(email: 'admin@local', password: 'wrong');
      } on InvalidCredentialsFailure {
        bad = true;
      }
      expect(bad, isTrue);
      bad = false;
      try {
        await repo.signIn(email: 'ghost@local', password: 'admin123');
      } on InvalidCredentialsFailure {
        bad = true;
      }
      expect(bad, isTrue);

      // معطّل → Unauthorized (مثل السحابة) وليس InvalidCredentials.
      await db.update(
        'profiles',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [adminId],
      );
      var blocked = false;
      try {
        await repo.signIn(email: 'admin@local', password: 'admin123');
      } on UnauthorizedFailure {
        blocked = true;
      }
      expect(blocked, isTrue);
      expect(repo.currentUser, isNull);
      await db.update(
        'profiles',
        {'is_active': 1},
        where: 'id = ?',
        whereArgs: [adminId],
      );

      // بث الحالة: دخول ثم خروج.
      final seen = <String?>[];
      final sub = repo.authState().listen((u) => seen.add(u?.id));
      await repo.signIn(email: 'admin@local', password: 'admin123');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen.contains(adminId), isTrue);
      expect(seen.last, isNull);
    } finally {
      LocalSession.clear();
      await db.close();
    }
  });

  test('users repository reads profiles/roles on sqlite', () async {
    final db = await _open();
    try {
      await _seedAdmin(db);
      final repo = UsersRepository(LocalDbClient(() async => db));
      final roles = await repo.listRoles();
      expect(roles.length, 3);
      final profiles = await repo.listProfiles();
      expect(profiles.length, 1);
      expect(profiles.first.email, 'admin@local');
      expect(profiles.first.isActive, isTrue);
      final overrides =
          await repo.pageOverrides(profiles.first.id);
      expect(overrides, isEmpty);
    } finally {
      await db.close();
    }
  });
}
