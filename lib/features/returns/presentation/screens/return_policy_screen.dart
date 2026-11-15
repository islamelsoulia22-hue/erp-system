import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/returns_repository.dart';

/// قسم سياسة المرتجعات (المدير فقط — users.manage).
///
/// المدير يحدد مدة المرتجع بعد إنشاء الفاتورة:
/// ساعة، ساعتين، يوم، يومين... أو بدون حد.
/// السيرفر يرفض إتمام أي مرتجع بعد انتهاء المدة.
class ReturnPolicyScreen extends ConsumerStatefulWidget {
  const ReturnPolicyScreen({super.key});

  @override
  ConsumerState<ReturnPolicyScreen> createState() =>
      _ReturnPolicyScreenState();
}

class _ReturnPolicyScreenState
    extends ConsumerState<ReturnPolicyScreen> {
  double? _salesHours;
  double? _purchaseHours;
  bool _init = false;
  bool _saving = false;

  static const _options = <double?>[
    null,
    1,
    2,
    6,
    12,
    24,
    48,
    72,
    168,
    336,
    720,
  ];

  void _maybeInit(ReturnPolicy p) {
    if (_init) return;
    _init = true;
    _salesHours = p.salesWindowHours;
    _purchaseHours = p.purchaseWindowHours;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(returnsRepositoryProvider).saveReturnPolicy(
            ReturnPolicy(
              salesWindowHours: _salesHours,
              purchaseWindowHours: _purchaseHours,
            ),
          );
      ref.invalidate(returnPolicyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سياسة المرتجعات.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر الحفظ.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.usersManage),
          orElse: () => false,
        );
    if (!canManage) {
      return const ResponsiveLayout(
        mobile: EmptyState(
          icon: Icons.lock_outline,
          title: 'للمدير فقط.',
          subtitle: 'سياسة المرتجعات يحددها مدير النظام.',
        ),
      );
    }
    final policy = ref.watch(returnPolicyProvider);
    return ResponsiveLayout(
      mobile: ListView(
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          policy.when(
            loading: () => const LoadingSkeleton(rows: 3),
            error: (_, _) => const ErrorState(
                message: 'تعذر تحميل السياسة.'),
            data: (p) {
              _maybeInit(p);
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                            title: 'مدة المرتجع بعد الفاتورة'),
                        const Text(
                          'بعد انتهاء المدة السيرفر بيرفض إتمام المرتجع تلقائيا. بدون حد = الوضع الحالي.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey),
                        ),
                        const SizedBox(
                            height: AppSpacing.md),
                        DropdownButtonFormField<
                            double?>(
                          initialValue: _salesHours,
                          decoration:
                              const InputDecoration(
                                  labelText:
                                      'مرتجع المبيعات'),
                          items: [
                            for (final h
                                in _options)
                              DropdownMenuItem(
                                  value: h,
                                  child: Text(
                                      ReturnPolicy.describe(
                                          h))),
                          ],
                          onChanged: (v) => setState(
                              () =>
                                  _salesHours = v),
                        ),
                        const SizedBox(
                            height: AppSpacing.sm),
                        DropdownButtonFormField<
                            double?>(
                          initialValue: _purchaseHours,
                          decoration:
                              const InputDecoration(
                                  labelText:
                                      'مرتجع المشتريات'),
                          items: [
                            for (final h
                                in _options)
                              DropdownMenuItem(
                                  value: h,
                                  child: Text(
                                      ReturnPolicy.describe(
                                          h))),
                          ],
                          onChanged: (v) => setState(
                              () =>
                                  _purchaseHours =
                                      v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                      height: AppSpacing.md),
                  FilledButton(
                    onPressed:
                        _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Colors.white))
                        : const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
