import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/date_filter.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/sales.dart';
import '../providers/sales_providers.dart';

const _statuses = <String?>[
  null,
  'DRAFT',
  'PENDING_APPROVAL',
  'APPROVED',
  'REJECTED',
];

/// Sales invoices: toolbar (search + status chips + new action),
/// data table on desktop, compact cards with badges on mobile.
/// Numbered pagination (10/page).
class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() =>
      _SalesListScreenState();
}

class _SalesListScreenState
    extends ConsumerState<SalesListScreen> {
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
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.salesCreate),
          orElse: () => false,
        );
    final status = ref.watch(salesStatusFilterProvider);
    final from = ref.watch(salesFromDateProvider);
    final to = ref.watch(salesToDateProvider);
    final page = ref.watch(salesPageProvider(_page));

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(salesPageProvider(_page).future),
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
                              'بحث برقم الفاتورة أو العميل',
                          onSubmitted: (v) {
                            ref
                                .read(salesSearchProvider
                                    .notifier)
                                .state = v;
                            _resetPage();
                          },
                          onClear: () {
                            ref
                                .read(salesSearchProvider
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
                              context.push('/sales/new'),
                          icon: const Icon(
                              Icons.add_outlined,
                              size: 18),
                          label:
                              const Text('فاتورة'),
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
                              label: Text(
                                  AppStatus.labelOf(
                                      s ?? '')),
                              selected: status == s,
                              visualDensity:
                                  VisualDensity.compact,
                              onSelected: (_) {
                                ref
                                    .read(
                                        salesStatusFilterProvider
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
                  DateFilterRow(
                    from: from,
                    to: to,
                    onFrom: (v) {
                      ref
                          .read(salesFromDateProvider
                              .notifier)
                          .state = v;
                      _resetPage();
                    },
                    onTo: (v) {
                      ref
                          .read(
                              salesToDateProvider.notifier)
                          .state = v;
                      _resetPage();
                    },
                    onClear: () {
                      ref
                          .read(salesFromDateProvider
                              .notifier)
                          .state = null;
                      ref
                          .read(
                              salesToDateProvider.notifier)
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
                    title: 'لا توجد فواتير',
                    subtitle: 'أنشئ أول فاتورة مبيعات',
                  )
                else
                  ResponsiveTable<SalesInvoice>(
                    columns: [
                      TableColumn(
                          label: 'الفاتورة',
                          value: (i) => i.number),
                      TableColumn(
                          label: 'العميل',
                          value: (i) =>
                              i.customerName ??
                              'عميل نقدي'),
                      TableColumn(
                          label: 'الحالة',
                          value: (i) => AppStatus
                              .labelOf(i.status)),
                      TableColumn(
                          label: 'السداد',
                          value: (i) => i.paymentStatus == 'PAID'
                              ? 'مدفوعة'
                              : i.paymentStatus == 'PARTIAL'
                                  ? 'جزئي'
                                  : 'آجل مستحق'),
                      TableColumn(
                          label: 'الإجمالي',
                          numeric: true,
                          value: (i) => AppFormat.money(
                              i.grandTotal,
                              suffix: '')),
                      TableColumn(
                          label: 'التاريخ',
                          value: (i) =>
                              AppFormat.date(i.createdAt)),
                    ],
                    rows: paged.items,
                    onTap: (i) =>
                        context.push('/sales/${i.id}'),
                    cardBuilder: (inv) => AppCard(
                      onTap: () => context
                          .push('/sales/${inv.id}'),
                      padding: const EdgeInsets.all(
                          AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(inv.number,
                                    textDirection:
                                        TextDirection.ltr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                Text(
                                  '${inv.customerName ?? 'عميل نقدي'} • ${AppFormat.date(inv.createdAt)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${AppFormat.money(inv.grandTotal)} • ${inv.paymentStatus == 'PAID' ? 'مدفوعة' : inv.paymentStatus == 'PARTIAL' ? 'جزئي (عربون)' : 'آجل مستحق'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge,
                                ),
                              ],
                            ),
                          ),
                          AppStatus.badge(inv.status),
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
