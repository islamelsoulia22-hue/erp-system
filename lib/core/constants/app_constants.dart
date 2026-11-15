// Central app-wide constants. Keep DB names in English, UI in Arabic.
abstract final class AppConstants {
  static const String appName = 'SANAD — سند';
  static const String supabaseUrlKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';

  static const int pageSize = 20;
  static const int barcodeSearchLimit = 50;

  /// عدد عناصر الصفحة الواحدة في ترقيم قوائم الأقسام.
  static const int listPageSize = 10;
}

abstract final class SupabaseTables {
  static const String profiles = 'profiles';
  static const String roles = 'roles';
  static const String permissions = 'permissions';
  static const String rolePermissions = 'role_permissions';
  static const String userRoles = 'user_roles';
}

abstract final class EnvKeys {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// رابط update.json (آخر Release). يُضبط في CI عبر .env أو --dart-define.
  /// للريبو الـ private يُستضاف على Supabase Storage (public bucket).
  static const String updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: '',
  );

  /// اسم bucket الـ releases على Supabase Storage (لاشتقاق رابط الـ manifest).
  static const String releasesBucket = String.fromEnvironment(
    'RELEASES_BUCKET',
    defaultValue: 'releases',
  );
}
