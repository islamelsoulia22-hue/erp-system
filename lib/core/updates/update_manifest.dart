import 'dart:convert';
import 'dart:io';

/// Update manifest (update.json) المنشور مع كل Release.
/// مثال:
/// {
///   "version": "1.2.3", "build": 101,
///   "minimum_supported_version": "1.2.3",
///   "windows": {"url": "https://...-Setup.exe"},
///   "android": {"url": "https://....apk"},
///   "ios": {"url": "", "store_url": "https://apps.apple.com/..."},
///   "release_notes": "...", "force_update": true
/// }
class UpdateManifest {
  final String version;
  final int build;
  final String minimumSupportedVersion;
  final String windowsUrl;
  final String androidUrl;
  final String androidArmeabiUrl;
  final String iosUrl;
  final String androidStoreUrl;
  final String iosStoreUrl;
  final String releaseNotes;
  final bool forceUpdate;

  const UpdateManifest({
    required this.version,
    required this.build,
    required this.minimumSupportedVersion,
    required this.windowsUrl,
    required this.androidUrl,
    required this.androidArmeabiUrl,
    required this.iosUrl,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  static String _str(Map<String, dynamic> m, String key) =>
      (m[key] as String?)?.trim() ?? '';

  static int _int(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  factory UpdateManifest.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic> section(Object? v) => v is Map
        ? Map<String, dynamic>.from(v)
        : <String, dynamic>{};
    final windows = section(m['windows']);
    final android = section(m['android']);
    final ios = section(m['ios']);
    return UpdateManifest(
      version: _str(m, 'version'),
      build: _int(m['build']),
      minimumSupportedVersion: _str(m, 'minimum_supported_version'),
      windowsUrl: _str(windows, 'url'),
      androidUrl: _str(android, 'url'),
      androidArmeabiUrl: _str(android, 'url_armeabi'),
      iosUrl: _str(ios, 'url'),
      androidStoreUrl: _str(android, 'store_url'),
      iosStoreUrl: _str(ios, 'store_url'),
      releaseNotes: _str(m, 'release_notes'),
      forceUpdate: m['force_update'] == true,
    );
  }
}

/// مقارنة Semantic Version: ترجع >0 لو a أحدث، 0 لو متساوية، <0 لو أقدم.
/// أي جزء غير رقمي يعتبر 0 (آمن ضد قيم فاسدة).
int compareSemver(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .split('.')
      .map((p) => int.tryParse(RegExp(r'\d+').firstMatch(p)?.group(0) ?? '') ?? 0)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// قرار التحديث بعد مقارنة النسخة الحالية بالـ manifest.
class UpdateDecision {
  final bool updateRequired;
  final UpdateManifest? manifest;
  final String currentVersion;
  final int currentBuild;

  const UpdateDecision({
    required this.updateRequired,
    required this.manifest,
    required this.currentVersion,
    required this.currentBuild,
  });

  static UpdateDecision decide({
    required String currentVersion,
    required int currentBuild,
    required UpdateManifest manifest,
  }) {
    final isNewer = manifest.build > currentBuild ||
        compareSemver(manifest.version, currentVersion) > 0;
    final belowMinimum = manifest.minimumSupportedVersion.isNotEmpty &&
        compareSemver(currentVersion, manifest.minimumSupportedVersion) < 0;
    return UpdateDecision(
      updateRequired: isNewer && (manifest.forceUpdate || belowMinimum),
      manifest: manifest,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }
}

/// تحميل update.json بمهلة قصيرة. أي فشل = null (التطبيق يكمل عادي).
Future<UpdateManifest?> fetchUpdateManifest(
  String url, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (url.isEmpty) return null;
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
    final res = await req.close().timeout(timeout);
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final manifest = UpdateManifest.fromMap(map);
    if (manifest.version.isEmpty) return null;
    return manifest;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
