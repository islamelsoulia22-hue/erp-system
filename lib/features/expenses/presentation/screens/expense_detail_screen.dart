import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/attachments/widgets/attachments_section.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sales/data/sales_repository.dart';
import '../../data/expenses_repository.dart';
import '../../domain/expense.dart';
import '../providers/expenses_providers.dart';

final _dfmt = DateFormat('yyyy/MM/dd');

/// صفحة المصروف: البيانات + الإجراءات (اعتماد/دفع) + المرفقات.
class ExpenseDetailScreen extends ConsumerWidget {
  final String expenseId;
  const ExpenseDetailScreen(
      {super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(expenseDetailProvider(expenseId));
    final myId =
        ref.watch(authRepositoryProvider).currentUser?.id;
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canApprove = perms.can(Permissions.expensesApprove);
    final canPay = perms.can(Permissions.expensesCreate) ||
        perms.can(Permissions.expensesEdit);
    final isCompanyManager = perms.isCompanyManager;

    return Scaffold(
      body: detail.when(
        loading: () => const LoadingSkeleton(rows: 6),
        error: (_, _) => const ErrorState(),
        data: (e) {
          if (e == null) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'المصروف غير موجود.',
            );
          }
          final isMine =
              e.createdBy != null && e.createdBy == myId;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(e.number,
                              textDirection:
                                  TextDirection.ltr,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall),
                          Text(e.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium),
                          Text(
                              '${e.categoryName ?? 'بدون تصنيف'} • ${_dfmt.format(e.expenseDate)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        Text(AppFormat.money(e.amount),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    color: AppColors
                                        .danger)),
                        Text(
                            expenseStatusAr(e.status,
                                e.paymentStatus),
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                        title: 'التفاصيل'),
                    _row('الجهة',
                        e.partyName ?? '—'),
                    _row('طريقة الدفع',
                        e.paymentMethodName ?? '—'),
                    _row('المرجع',
                        e.referenceNumber ?? '—'),
                    _row('المخزن/الفرع',
                        e.warehouseName ?? '—'),
                    if (e.notes != null)
                      _row('ملاحظات', e.notes!),
                    if (e.rejectionReason != null)
                      _row('سبب الرفض',
                          e.rejectionReason!),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                        title: 'الإجراءات'),
                    if (e.editable)
                      FilledButton(
                        onPressed: () => _act(
                            context,
                            ref,
                            () => ref
                                .read(
                                    expensesRepositoryProvider)
                                .submit(e.id)),
                        child:
                            const Text('إرسال للاعتماد'),
                      ),
                    if (e.pending &&
                        canApprove &&
                        (!isMine || isCompanyManager)) ...[
                      FilledButton(
                        onPressed: () => _act(
                            context,
                            ref,
                            () => ref
                                .read(
                                    expensesRepositoryProvider)
                                .approve(e.id)),
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                AppColors.success),
                        child: const Text('اعتماد'),
                      ),
                      const SizedBox(
                          height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: () => _rejectSheet(
                            context, ref, e.id),
                        child:
                            const Text('رفض بسبب'),
                      ),
                    ],
                    if (e.pending &&
                        isMine &&
                        !isCompanyManager)
                      const Text(
                          'مصروفك بانتظار الاعتماد.',
                          textAlign: TextAlign.center),
                    if (e.pending && !canApprove)
                      const Text(
                          'المصروف قيد المراجعة — الاعتماد للمدير فقط.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey)),
                    // الاعتماد ≠ الدفع: تسجيل الدفع بعد الاعتماد.
                    if (e.status == 'APPROVED' &&
                        !e.isPaid &&
                        canPay) ...[
                      const SizedBox(
                          height: AppSpacing.sm),
                      FilledButton.tonal(
                        onPressed: () => _paySheet(
                            context, ref, e),
                        child:
                            const Text('تسجيل الدفع'),
                      ),
                    ],
                    if (e.isPaid)
                      const Text('تم دفع هذا المصروف.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.green)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: AttachmentsSection(
                    entityType: 'EXPENSE',
                    entityId: e.id),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Expanded(
              child: Text(v,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(expenseDetailProvider(expenseId))
        ..invalidate(expensesPageProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  void _rejectSheet(
      BuildContext context, WidgetRef ref, String id) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text('سبب الرفض *',
                style: TextStyle(
                    fontWeight: FontWeight.bold)),
            TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                    labelText: 'السبب')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop();
                await _act(
                    context,
                    ref,
                    () => ref
                        .read(expensesRepositoryProvider)
                        .reject(id, ctrl.text.trim()));
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
  }

  void _paySheet(
      BuildContext context, WidgetRef ref, Expense e) {
    String? methodId = e.paymentMethodId;
    final refCtrl =
        TextEditingController(text: e.referenceNumber ?? '');
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder(
        future: ref
            .read(salesRepositoryProvider)
            .paymentMethods(),
        builder: (ctx, snap) {
          final methods = snap.data ?? [];
          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom +
                    16),
            child: StatefulBuilder(
              builder: (ctx, setS) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'تسجيل دفع ${AppFormat.money(e.amount)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: methodId,
                    decoration: const InputDecoration(
                        labelText: 'طريقة الدفع'),
                    items: [
                      for (final m in methods)
                        DropdownMenuItem(
                            value: m['id'] as String,
                            child: Text((m['name_ar'] ??
                                    m['code'])
                                .toString())),
                    ],
                    onChanged: (v) =>
                        setS(() => methodId = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: refCtrl,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'رقم المرجع (اختياري)')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _act(
                          context,
                          ref,
                          () => ref
                              .read(
                                  expensesRepositoryProvider)
                              .pay(e.id,
                                  methodId: methodId,
                                  reference:
                                      refCtrl.text));
                    },
                    child: const Text('تأكيد الدفع'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
