import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/backend/backend_mode.dart';
import 'core/constants/app_constants.dart';
import 'core/local/local_database.dart';
import 'core/local/local_query.dart';

/// BACKEND=supabase (افتراضي): نسخة السحابة.
/// BACKEND=local: نسخة الجهاز (SQLite — بدون سوبابيز) **بنفس
/// شاشات السحابة** (المصاريف/الموافقات/التصنيع مستبعدة).
/// مثال: flutter run --dart-define=BACKEND=local
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (resolveBackendMode() == BackendMode.local) {
    await LocalDatabase.instance.ready();
    // استعادة جلسة الجهاز المحفوظة (تبقي الدخول بعد إعادة التشغيل).
    try {
      await LocalSession.restore(await LocalDatabase.instance.db);
    } catch (_) {}
    runApp(const ProviderScope(child: ErpApp()));
    return;
  }

  // Load .env if bundled; fallback to --dart-define.
  // dotenv.maybeGet throws when load failed, so keep all access in try.
  var url = EnvKeys.supabaseUrl;
  var anonKey = EnvKeys.supabaseAnonKey;
  try {
    await dotenv.load(fileName: '.env');
    final u = dotenv.maybeGet('SUPABASE_URL');
    if (u?.isNotEmpty == true) url = u!;
    final k = dotenv.maybeGet('SUPABASE_ANON_KEY');
    
    if (k?.isNotEmpty == true) anonKey = k!;
  } catch (_) {
    // .env optional when using --dart-define.
  }

  if (url.isNotEmpty && anonKey.isNotEmpty) {
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: anonKey);
  } else {
    debugPrint('SUPABASE_URL/ANON_KEY missing: running in UI-shell mode.');
  }

  runApp(const ProviderScope(child: ErpApp()));
}
