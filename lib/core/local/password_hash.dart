import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// تشفير باسورد النسخة اللوكال: SHA-256 + ملح عشوائي
/// لكل مستخدم. (ملف منفصل عشان قاعدة البيانات والريبوزيتوري
/// يستخدموه من غير استيراد دائري).
/// باسورد المدير الافتراضي لأول تشغيل لوكال.
/// تظهر كتلميح في شاشة الدخول — غيرها بعد أول دخول.
const kDefaultAdminPassword = 'admin123';

class PasswordHash {
  const PasswordHash._();

  static String generateSalt([int bytes = 16]) {
    final r = Random.secure();
    final raw = List.generate(bytes, (_) => r.nextInt(256));
    return base64Url.encode(raw);
  }

  static String hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt::$password')).toString();
  }

  static bool verify(String password, String salt, String expected) {
    if (salt.isEmpty || expected.isEmpty) return false;
    final actual = hash(password, salt);
    if (actual.length != expected.length) return false;
    // مقارنة ثابتة الزمن ضد هجمات التوقيت.
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }
}
