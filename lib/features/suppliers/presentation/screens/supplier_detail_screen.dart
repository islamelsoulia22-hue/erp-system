import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../payments/data/payments_repository.dart';
import '../../../products/presentation/providers/products_providers.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../purchases/domain/purchases.dart';
import '../../data/suppliers_repository.dart';
import '../providers/suppliers_providers.dart';

class SupplierDetailScreen extends ConsumerStatefulWidget {
  final String supplierId;
  const SupplierDetailScreen({super.key, required this.supplierId});

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState
    extends ConsumerState<SupplierDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final detail =
        ref.watch(supplierDetailProvider(widget.supplierId));
    final canEdit = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.suppliersEdit),
          orElse: () => false,
        );
    final isManager = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.isCompanyManager,
          orElse: () => false,
        );
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 5),
      error: (_, _) => const ErrorState(),
      data: (s) {
        if (s == null) {
          return const EmptyState(
            icon: Icons.handshake_outlined,
            title: 'المورد غير موجود.',
          );
        }
        return ResponsiveLayout(
          mobile: ListView(
            padding:
                EdgeInsets.all(context.contentPadding),
            children: [
              AppCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          AppColors.primaryContainer,
                      child: Text(
                          s.name.isNotEmpty
                              ? s.name[0]
                              : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight:
                                  FontWeight.w700,
                              fontSize: 20)),
                    ),
                    const SizedBox(
                        width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall),
                          Text(s.code,
                              textDirection:
                                  TextDirection.ltr,
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
                        AppStatus.badge(s.isActive
                            ? 'ACTIVE'
                            : 'INACTIVE'),
                        if (canEdit)
                          IconButton(
                            tooltip: 'تعديل',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.edit_outlined),
                            onPressed: () => context.push(
                                '/suppliers/${widget.supplierId}/edit'),
                          ),
                        if (isManager)
                          IconButton(
                            tooltip: 'حذف المورد',
                            iconSize: 20,
                            icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger),
                            onPressed: () =>
                                _deleteSupplier(
                                    context,
                                    ref,
                                    widget.supplierId,
                                    s.name),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(
                  height: AppSpacing.md),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      label: Text('نظرة عامة')),
                  ButtonSegment(
                      value: 1,
                      label: Text('المشتريات')),
                ],
                selected: {_tab},
                onSelectionChanged: (st) =>
                    setState(() => _tab = st.first),
              ),
              const SizedBox(
                  height: AppSpacing.md),
              if (_tab == 0) ...[
                AppCard(
                  child: Column(
                    children: [
                      _row(context, 'الهاتف',
                          s.phone ?? '—'),
                      _row(context, 'العنوان',
                          s.address ?? '—'),
                      if (s.company?.isNotEmpty == true)
                        _row(context, 'الشركة',
                            s.company!),
                      _SupplyCategoryRow(
                          categoryId:
                              s.supplyCategoryId),
                      if (s.notes != null)
                        _row(context, 'ملاحظات',
                            s.notes!),
                    ],
                  ),
                ),
                const SizedBox(
                    height: AppSpacing.md),
                FutureBuilder(
                  future: ref
                      .read(paymentsRepositoryProvider)
                      .supplierBalance(s.id),
                  builder: (context, snap) {
                    final b = snap.data;
                    return AppCard(
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors
                                  .purpleContainer,
                              borderRadius:
                                  BorderRadius.circular(
                                      8),
                            ),
                            child: const Icon(
                                Icons
                                    .account_balance_wallet_outlined,
                                color:
                                    AppColors.purple),
                          ),
                          const SizedBox(
                              width: AppSpacing.sm),
                          Expanded(
                            child: b == null
                                ? Text(
                                    'جاري حساب الرصيد...',
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .bodyMedium)
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'مستحق ${AppFormat.money(b.outstanding)}',
                                        style: Theme.of(
                                                context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        'إجمالي ${AppFormat.money(b.total)} • مدفوع ${AppFormat.money(b.paid)}',
                                        style: Theme.of(
                                                context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ] else
                FutureBuilder<List<PurchaseInvoice>>(
                  future: ref
                      .read(purchasesRepositoryProvider)
                      .listInvoices(
                          supplierId:
                              widget.supplierId),
                  builder: (context, snap) {
                    if (snap.connectionState ==
                        ConnectionState.waiting) {
                      return const LoadingSkeleton(
                          rows: 4);
                    }
                    if (snap.hasError) {
                      return const ErrorState(
                          message:
                              'تعذر تحميل الفواتير.');
                    }
                    final rows = snap.data ?? [];
                    if (rows.isEmpty) {
                      return const EmptyState(
                        icon: Icons
                            .receipt_long_outlined,
                        title:
                            'لا توجد فواتير لهذا المورد',
                      );
                    }
                    return AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < rows.length;
                              i++) ...[
                            ListTile(
                              dense: true,
                              title: Text(
                                  rows[i].number,
                                  textDirection:
                                      TextDirection
                                          .ltr),
                              subtitle: Text(
                                  '${AppStatus.labelOf(rows[i].status)} • ${AppFormat.money(rows[i].grandTotal)}'),
                              trailing:
                                  AppStatus.badge(
                                      rows[i].status),
                              onTap: () =>
                                  context.push(
                                      '/purchase-invoices/${rows[i].id}'),
                            ),
                            if (i < rows.length - 1)
                              const Divider(
                                  height: 1),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSupplier(BuildContext context, WidgetRef ref,
      String id, String name) async {
    if (!await confirmDelete(context, 'المورد "$name"')) return;
    try {
      await ref.read(suppliersRepositoryProvider).deleteSupplier(id);
      ref
        ..invalidate(suppliersPageProvider)
        ..invalidate(supplierDetailProvider(id));
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(deleteErrorMessage(e))));
      }
    }
  }

  Widget _row(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(children: [
        Expanded(
            child:
                Text(k, style: theme.textTheme.bodyMedium)),
        Flexible(
          child: Text(
            v,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

/// يعرض اسم فئة التوريد من الـ id (اختياري).
class _SupplyCategoryRow extends ConsumerWidget {
  final String? categoryId;
  const _SupplyCategoryRow({this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categoryId == null) {
      return const SizedBox.shrink();
    }
    final cats = ref.watch(productCategoriesProvider);
    final name = cats.maybeWhen(
      data: (list) {
        for (final c in list) {
          if (c.id == categoryId) return c.display;
        }
        return '—';
      },
      orElse: () => '...',
    );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(children: [
        Expanded(
            child: Text('بيورد',
                style: theme.textTheme.bodyMedium)),
        Flexible(
          child: Text(
            name,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
