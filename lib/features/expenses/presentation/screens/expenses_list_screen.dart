import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/date_filter.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/expense.dart';
import '../providers/expenses_providers.dart';

const _statuses = <String?>[
  null,
  'DRAFT',
  'PENDING_APPROVAL',
  'APPROVED_UNPAID',
  'PAID',
  'REJECTED',
];

String _statusLabel(String? s) {
  return switch (s) {
    null => 'الكل',
    'DRAFT' => 'مسودة',
    'PENDING_APPROVAL' => 'بانتظار الاعتماد',
    'APPROVED_UNPAID' => 'معتمدة (غير مدفوعة)',
    'PAID' => 'مدفوعة',
    'REJECTED' => 'مرفوضة',
    _ => s,
  };
}

Color _statusColor(Expense e) {  if (e.isPaid) return AppColors.success;
  return switch (e.status) {
    'DRAFT' => Colors.grey,
    'PENDING_APPROVAL' => AppColors.warning,
    'APPROVED' => AppColors.info,
    'REJECTED' => AppColors.danger,
    _ => Colors.grey,
  };
}

/// قائمة المصروفات: بحث + حالة + تصنيف + تاريخ + إنشاء.
class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() =>
      _ExpensesListScreenState();
}

class _ExpensesListScreenState
    extends ConsumerState<ExpensesListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  void _resetPage() {
    if (_page != 0) setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canCreate = perms.can(Permissions.expensesCreate);
    final isManager = perms.isCompanyManager;
    final status = ref.watch(expenseStatusProvider);
    final categoryId = ref.watch(expenseCategoryProvider);
    final from = ref.watch(expenseFromDateProvider);
    final to = ref.watch(expenseToDateProvider);
    final cats = ref.watch(expenseCategoriesProvider);
    final page = ref.watch(expensesPageProvider(_page));

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(expensesPageProvider(_page).future),
        child: ListView(
          controller: _scroll,
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SearchField(
                          controller: _search,
                          hint:
                              'بحث برقم المصروف أو البيان أو الجهة',
                          onSubmitted: (v) {
                            ref
                                .read(expenseSearchProvider
                                    .notifier)
                                .state = v;
                            _resetPage();
                          },
                          onClear: () {
                            ref
                                .read(expenseSearchProvider
                                    .notifier)
                                .state = '';
                            _resetPage();
                          },
                        ),
                      ),
                      if (canCreate) ...[
                        const SizedBox(
                            width: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: () =>
                              context.push('/expenses/new'),
                          icon: const Icon(
                              Icons.add_outlined,
                              size: 18),
                          label:
                              const Text('مصروف'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in _statuses)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional
                                    .only(end: 6),
                            child: ChoiceChip(
                              label:
                                  Text(_statusLabel(s)),
                              selected: status == s,
                              visualDensity:
                                  VisualDensity.compact,
                              onSelected: (_) {
                                ref
                                    .read(expenseStatusProvider
                                        .notifier)
                                    .state = s;
                                _resetPage();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: cats.maybeWhen(
                          data: (list) =>
                              DropdownButtonFormField<
                                  String?>(
                            initialValue: categoryId,
                            decoration:
                                const InputDecoration(
                                    labelText:
                                        'التصنيف',
                                    isDense: true),
                            items: [
                              const DropdownMenuItem(
                                  value: null,
                                  child:
                                      Text('كل التصنيفات')),
                              for (final c in list)
                                DropdownMenuItem(
                                    value: c.id,
                                    child: Text(
                                        c.display,
                                        overflow:
                                            TextOverflow
                                                .ellipsis)),
                            ],
                            onChanged: (v) {
                              ref
                                  .read(
                                      expenseCategoryProvider
                                          .notifier)
                                  .state = v;
                              _resetPage();
                            },
                          ),
                          orElse: () =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      if (isManager) ...[
                        const SizedBox(
                            width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: () => context.push(
                              '/expenses/categories'),
                          icon: const Icon(
                              Icons.category_outlined,
                              size: 18),
                          label:
                              const Text('التصنيفات'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DateFilterRow(
                    from: from,
                    to: to,
                    onFrom: (v) {
                      ref
                          .read(expenseFromDateProvider
                              .notifier)
                          .state = v;
                      _resetPage();
                    },
                    onTo: (v) {
                      ref
                          .read(
                              expenseToDateProvider
                                  .notifier)
                          .state = v;
                      _resetPage();
                    },
                    onClear: () {
                      ref
                          .read(expenseFromDateProvider
                              .notifier)
                          .state = null;
                      ref
                          .read(
                              expenseToDateProvider
                                  .notifier)
                          .state = null;
                      _resetPage();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...page.when(
              loading: () => [
                const Padding(
                  padding:
                      EdgeInsets.all(AppSpacing.mdx),
                  child: Center(
                      child:
                          CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [
                const Center(
                    child: Text(
                        'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.')),
              ],
              data: (paged) => [
                if (paged.items.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد مصروفات',
                    subtitle: 'أنشئ أول مصروف',
                  )
                else
                  ResponsiveTable<Expense>(
                columns: [
                  TableColumn(
                      label: 'المصروف',
                      value: (e) => e.number),
                  TableColumn(
                      label: 'البيان',
                      value: (e) => e.title),
                  TableColumn(
                      label: 'التصنيف',
                      value: (e) =>
                          e.categoryName ?? '—'),
                  TableColumn(
                      label: 'الحالة',
                      value: (e) => expenseStatusAr(
                          e.status, e.paymentStatus)),
                  TableColumn(
                      label: 'المبلغ',
                      numeric: true,
                      value: (e) => AppFormat.money(
                          e.amount,
                          suffix: '')),
                  TableColumn(
                      label: 'التاريخ',
                      value: (e) =>
                          AppFormat.date(e.expenseDate)),
                ],
                rows: paged.items,
                onTap: (e) =>
                    context.push('/expenses/${e.id}'),
                cardBuilder: (e) => AppCard(
                  onTap: () =>
                      context.push('/expenses/${e.id}'),
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
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
                                    .titleSmall),
                            Text(
                              '${e.title} • ${e.categoryName ?? 'بدون تصنيف'}',
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                            Text(
                              '${AppFormat.money(e.amount)} • ${AppFormat.date(e.expenseDate)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(e)
                              .withValues(alpha: 0.15),
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text(
                          expenseStatusAr(e.status,
                              e.paymentStatus),
                          style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(e),
                              fontWeight:
                                  FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                AppPagination(
                  page: _page,
                  total: paged.total,
                  onGo: _go,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
