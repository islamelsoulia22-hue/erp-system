import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/maintenance_repository.dart';

/// قسم الصيانة والإصلاح (المدير فقط).
///
/// فيه زرار "مسح كل البيانات" اللي بيمسح كل بيانات الشغل
/// (فواتير/مخزون/عملاء/موردون/منتجات/مصروفات/...) ويحافظ على
/// المستخدمين والأدوار والصلاحيات فقط — عشان تبدأ على نظافة.
///
/// الحماية طبقتين:
/// 1) القائمة نفسها لا تظهر إلا لمن معه صلاحية users.manage.
/// 2) دالة السيرفر ترفض أي منادٍ بدون الصلاحية (RLS هو الحارس الحقيقي).
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() =>
      _MaintenanceScreenState();
}

class _MaintenanceScreenState
    extends ConsumerState<MaintenanceScreen> {
  bool _running = false;

  static const _wiped = [
    'فواتير وطلبات المبيعات والمشتريات بأصنافها',
    'المدفوعات والشحنات والمرتجعات',
    'طلبات التوريد وأوامر التصنيع والأصناف المخصصة',
    'العملاء والموردون والمنتجات والمخازن والمخزون',
    'المصروفات والمرفقات والموافقات والسجلات والإشعارات',
    'تصفير كل عدّادات الترقيم (تبدأ من 000001)',
  ];

  static const _kept = [
    'المستخدمون (الحسابات وكلمات المرور كما هي)',
    'الأدوار والصلاحيات وإعدادات ظهور الصفحات',
    'بيانات التأسيس: طرق الدفع، الوحدات، التصنيفات، إعدادات التطبيق',
  ];

  Future<void> _onReset() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل البيانات؟'),
        content: const Text(
          'سيتم حذف كل بيانات الشغل نهائيا ولا يمكن التراجع.\n'
          'سيبقى المستخدمون والأدوار فقط.\n\n'
          'هل أنت متأكد أنك تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    // تأكيد ثانٍ بالكتابة لمنع الضغط بالخطأ.
    // (ودجت مستقل يملك الـ Controller ويمسحه بعد فكّه من الشجرة —
    //  المسح المباشر بعد pop كان بيكسر الـ TextField).
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _TypeToConfirmDialog(),
    );
    if (second != true || !mounted) return;

    setState(() => _running = true);
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .resetAllData();
      // تحديث كل الشاشات بعد المسح.
      ref.invalidate(maintenanceRepositoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم مسح كل البيانات بنجاح. المستخدمون كما هم — ابدأ على نظافة.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AppFailure
                ? e.messageAr
                : 'تعذر مسح البيانات، برجاء المحاولة مرة أخرى.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.build_outlined,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الصيانة والإصلاح',
                              style: theme
                                  .textTheme
                                  .titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'أدوات خطيرة للمدير فقط — استخدمها بحذر.',
                              style: theme
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons
                                .delete_forever_outlined,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'منطقة الخطر',
                            style: theme
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color:
                                      AppColors.danger,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'مسح كل البيانات والبدء على نظافة (مع الحفاظ على المستخدمين فقط).',
                        style:
                            theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'سيتم حذف:',
                        style: theme
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      for (final t in _wiped)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Text(
                                '• ',
                                style: TextStyle(
                                  color:
                                      AppColors.danger,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  t,
                                  style: theme
                                      .textTheme
                                      .bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'سيتم الحفاظ على:',
                        style: theme
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      for (final t in _kept)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const Text(
                                '• ',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  t,
                                  style: theme
                                      .textTheme
                                      .bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style:
                            FilledButton.styleFrom(
                              backgroundColor:
                                  AppColors.danger,
                              padding:
                                  const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                            ),
                        onPressed: _running
                            ? null
                            : _onReset,
                        icon: _running
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors
                                          .white,
                                    ),
                              )
                            : const Icon(
                                Icons
                                    .delete_forever_outlined,
                              ),
                        label: Text(
                          _running
                              ? 'جارٍ المسح...'
                              : 'مسح كل البيانات',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// حوار التأكيد النهائي: لازم كتابة "مسح" لتفعيل زر الحذف.
/// StatefulWidget مستقل حتى يُمسح الـ Controller بعد فكّ الودجت
/// من الشجرة (وليس لحظة الـ pop) — وإلا يرمي
/// "controller used after dispose".
class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog();

  @override
  State<_TypeToConfirmDialog> createState() =>
      _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState
    extends State<_TypeToConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تأكيد نهائي'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'اكتب كلمة "مسح" في الخانة لتفعيل زر الحذف النهائي.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اكتب: مسح',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
          ),
          onPressed: _ctrl.text.trim() == 'مسح'
              ? () =>
                    Navigator.of(context).pop(true)
              : null,
          child: const Text('حذف نهائي'),
        ),
      ],
    );
  }
}
