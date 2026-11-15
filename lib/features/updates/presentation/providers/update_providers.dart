import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/updates/update_manifest.dart';

/// رابط update.json:
/// 1) UPDATE_MANIFEST_URL من .env أو --dart-define (يكتبه CI تلقائيا).
/// 2) اشتقاقه من SUPABASE_URL + bucket (الريبو private → الاستضافة على Storage).
/// 3) فارغ = لا فحص (التطبيق يكمل عادي).
String resolveUpdateManifestUrl() {
  try {
    final fromEnv = dotenv.maybeGet('UPDATE_MANIFEST_URL');
    if (fromEnv?.isNotEmpty == true) return fromEnv!;
  } catch (_) {}
  if (EnvKeys.updateManifestUrl.isNotEmpty) {
    return EnvKeys.updateManifestUrl;
  }
  var supabaseUrl = EnvKeys.supabaseUrl;
  var bucket = EnvKeys.releasesBucket;
  try {
    final u = dotenv.maybeGet('SUPABASE_URL');
    if (u?.isNotEmpty == true) supabaseUrl = u!;
    final b = dotenv.maybeGet('RELEASES_BUCKET');
    if (b?.isNotEmpty == true) bucket = b!;
  } catch (_) {}
  if (supabaseUrl.isEmpty) return '';
  final base = supabaseUrl.endsWith('/')
      ? supabaseUrl.substring(0, supabaseUrl.length - 1)
      : supabaseUrl;
  return '$base/storage/v1/object/public/$bucket/update.json';
}

/// فحص التحديث عند بدء التشغيل.
/// - لا يوجد manifest / لا إنترنت = يكمل التطبيق عادي (fail-open).
/// - نسخة أحدث + (force_update أو تحت الحد الأدنى) = إجباري.
final updateCheckProvider =
    FutureProvider.autoDispose<UpdateDecision>((ref) async {
  // موقوف مؤقتا للاختبار (debug على التليفون) — لا يحجب التطبيق أبدا.
  // لما تخلص اختبار شيل السطر ده ورجع الفحص.
  return const UpdateDecision(
    updateRequired: false,
    manifest: null,
    currentVersion: 'dev',
    currentBuild: 0,
  );
  // ignore: dead_code
  var currentVersion = '0.0.0';
  var currentBuild = 0;
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) currentVersion = info.version;
    currentBuild = int.tryParse(info.buildNumber) ?? 0;
  } catch (_) {
    // بدون بيانات النسخة لا يمكن المقارنة — اسمح بالدخول.
    return UpdateDecision(
      updateRequired: false,
      manifest: null,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }
  final manifest =
      await fetchUpdateManifest(resolveUpdateManifestUrl());
  if (manifest == null) {
    return UpdateDecision(
      updateRequired: false,
      manifest: null,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }
  return UpdateDecision.decide(
    currentVersion: currentVersion,
    currentBuild: currentBuild,
    manifest: manifest,
  );
});
