import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/updates/update_manifest.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../providers/update_providers.dart';

/// شاشة حاجبة: لا يعمل التطبيق حتى يتم التحديث.
/// - Windows: تحميل Setup.exe ثم تشغيله (بموافقة المستخدم عبر الزرار).
/// - Android/iOS: توجيه للمتجر أو تحميل الملف (لا تثبيت مباشر من التطبيق).
class ForceUpdateScreen extends ConsumerStatefulWidget {
  final UpdateDecision decision;
  const ForceUpdateScreen({super.key, required this.decision});

  @override
  ConsumerState<ForceUpdateScreen> createState() =>
      _ForceUpdateScreenState();
}

class _ForceUpdateScreenState
    extends ConsumerState<ForceUpdateScreen> {
  double? _progress;
  String? _status;
  bool _busy = false;

  UpdateManifest get _m => widget.decision.manifest!;

  /// الرابط المناسب للمنصة الحالية.
  /// Android: نسخة arm64 افتراضيا، ونسخة armeabi للأجهزة 32-bit القديمة
  /// (الـ APKs مقسمة لكل معمارية لتبقى تحت حد الـ Storage).
  String _urlForPlatform() {
    if (Platform.isWindows) return _m.windowsUrl;
    if (Platform.isAndroid) {
      if (_m.androidStoreUrl.isNotEmpty) return _m.androidStoreUrl;
      try {
        if (Abi.current() == Abi.androidArm &&
            _m.androidArmeabiUrl.isNotEmpty) {
          return _m.androidArmeabiUrl;
        }
      } catch (_) {}
      return _m.androidUrl;
    }
    if (Platform.isIOS) return _m.iosStoreUrl;
    return _m.windowsUrl;
  }

  Future<void> _onUpdatePressed() async {
    final url = _urlForPlatform();
    if (url.isEmpty) {
      setState(() => _status =
          'رابط التحديث غير متوفر لهذه المنصة — تواصل مع الإدارة.');
      return;
    }
    if (Platform.isWindows) {
      await _downloadAndRunWindows(url);
      return;
    }
    // موبايل: توجيه للمتجر/المتصفح فقط — لا تثبيت مباشر من التطبيق.
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(
            () => _status = 'تعذر فتح رابط التحديث.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _status = 'تعذر فتح رابط التحديث.');
      }
    }
  }

  /// Windows: تحميل الـ Setup مع تقدم، ثم تشغيله وإغلاق التطبيق.
  /// لا يتم أي تثبيت صامت — المستخدم هو من ضغط "تحديث الآن".
  Future<void> _downloadAndRunWindows(String url) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'جاري تحميل التحديث...';
    });
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw 'فشل التحميل (${res.statusCode})';
      }
      final total = res.contentLength > 0 ? res.contentLength : null;
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}sanad-Setup.exe');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted && total != null) {
          setState(() => _progress = received / total);
        }
      }
      await sink.close();
      if (!mounted) return;
      setState(() {
        _status = 'تم التحميل — جاري تشغيل المثبت...';
        _progress = null;
      });
      await Process.start(file.path, []);
      exit(0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'تعذر التحديث: $e — حاول مجددا.';
          _progress = null;
          _busy = false;
        });
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.mdx),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandLogo(size: 72, radius: 18),
                const SizedBox(height: AppSpacing.mdx),
                Text('تحديث جديد متوفر',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'النسخة الحالية: ${d.currentVersion}+${d.currentBuild}\nالنسخة الجديدة: ${_m.version}+${_m.build}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (_m.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(_m.releaseNotes,
                        style: theme.textTheme.bodySmall),
                  ),
                ],
                const SizedBox(height: AppSpacing.mdx),
                if (_progress != null)
                  Column(
                    children: [
                      LinearProgressIndicator(
                          value: _progress),
                      const SizedBox(
                          height: AppSpacing.sm),
                    ],
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _busy && _progress == null
                            ? null
                            : _onUpdatePressed,
                    icon: const Icon(
                        Icons.system_update_outlined),
                    label: Text(_busy
                        ? 'جاري التحديث...'
                        : 'تحديث الآن'),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_status!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(
                              color: AppColors.danger)),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => ref
                      .invalidate(updateCheckProvider),
                  icon: const Icon(
                      Icons.refresh_outlined,
                      size: 18),
                  label:
                      const Text('إعادة فحص التحديث'),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'يجب تثبيت التحديث لمتابعة استخدام التطبيق.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
