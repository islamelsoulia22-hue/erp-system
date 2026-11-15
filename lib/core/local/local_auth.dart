import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_database.dart';
import 'password_hash.dart';

/// خطأ دخول محلي برسالة عربية جاهزة للعرض.
class LocalAuthFailure implements Exception {
  final String messageAr;
  const LocalAuthFailure(this.messageAr);

  @override
  String toString() => messageAr;
}

/// مستخدم محلي (نسخة الجهاز).
class LocalUser {
  final String id;
  final String fullName;
  final String email;
  const LocalUser({
    required this.id,
    required this.fullName,
    required this.email,
  });

  factory LocalUser.fromMap(Map<String, Object?> m) {
    return LocalUser(
      id: (m['id'] as String?) ?? '',
      fullName: (m['full_name'] as String?) ?? 'مستخدم',
      email: (m['email'] as String?) ?? '',
    );
  }
}

/// مصادقة النسخة اللوكال: دخول بالإيميل + باسورد مشفر،
/// وجلسة واحدة محفوظة في القاعدة. يأخذ دالة فتح القاعدة
/// كحقن عشان الاختبار بقاعدة in-memory.
class LocalAuthRepository {
  final Future<Database> Function() _open;
  LocalAuthRepository(this._open);

  /// المستخدم صاحب الجلسة الحالية، أو null.
  Future<LocalUser?> currentUser() async {
    final db = await _open();
    final rows = await db.rawQuery('''
SELECT u.id, u.full_name, u.email FROM local_session s
JOIN users u ON u.id = s.user_id AND u.is_active = 1
WHERE s.id = 1
''');
    if (rows.isEmpty) return null;
    return LocalUser.fromMap(rows.first);
  }

  /// دخول: يتحقق من الباسورد ويفتح جلسة. يرمي
  /// LocalAuthFailure برسالة عربية عند الفشل.
  Future<LocalUser> login({
    required String email,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    if (mail.isEmpty || password.isEmpty) {
      throw const LocalAuthFailure('ادخل الإيميل والباسورد.');
    }
    final db = await _open();
    final rows = await db.query('users', where: 'is_active = 1');
    Map<String, Object?>? hit;
    for (final r in rows) {
      final e = ((r['email'] as String?) ?? '').trim().toLowerCase();
      if (e == mail) {
        hit = r;
        break;
      }
    }
    if (hit == null) {
      throw const LocalAuthFailure('بيانات الدخول غير صحيحة.');
    }
    final ok = PasswordHash.verify(
      password,
      (hit['password_salt'] as String?) ?? '',
      (hit['password_hash'] as String?) ?? '',
    );
    if (!ok) {
      throw const LocalAuthFailure('بيانات الدخول غير صحيحة.');
    }
    final user = LocalUser.fromMap(hit);
    await db.insert('local_session', {
      'id': 1,
      'user_id': user.id,
      'started_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return user;
  }

  /// خروج: يمسح الجلسة.
  Future<void> logout() async {
    final db = await _open();
    await db.delete('local_session', where: 'id = 1');
  }
}

final localAuthRepositoryProvider = Provider<LocalAuthRepository>((ref) {
  return LocalAuthRepository(() => LocalDatabase.instance.db);
});

/// جلسة اللوكال الحالية (تُبطل بعد الدخول/الخروج).
final localSessionProvider = FutureProvider.autoDispose<LocalUser?>((ref) {
  return ref.watch(localAuthRepositoryProvider).currentUser();
});
