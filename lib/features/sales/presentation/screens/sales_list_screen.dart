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
import '../../../../core/widgets/yad_widgets.dart';
import '../../../../core/theme/app_colors.dart';
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
                        GradientButton(
                          label: 'فاتورة',
                          icon: Icons.add,
                          height: 50,
                          onPressed: () =>
                              context.push('/sales/new'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  YadFilterBar(
                    labels: [
                      for (final st in _statuses)
                        st == null ? 'الكل' : AppStatus.labelOf(st),
                    ],
                    selected: _statuses.indexOf(status) < 0
                        ? 0
                        : _statuses.indexOf(status),
                    onChanged: (i) {
                      ref
                          .read(salesStatusFilterProvider.notifier)
                          .state = _statuses[i];
                      _resetPage();
                    },
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
                if (paged.items.isNotEmpty) ...[
                  _SalesSummary(
                    total: paged.total,
                    pageSum: paged.items
                        .fold<double>(0, (a, i) => a + i.grandTotal),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
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
                    cardBuilder: (inv) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: AppCard(
                        onTap: () =>
                            context.push('/sales/${inv.id}'),
                        child: Row(
                          children: [
                            const YadIconTile(
                                icon: Icons.receipt_long_outlined,
                                size: 46,
                                radius: 16),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(inv.number,
                                      textDirection:
                                          TextDirection.ltr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${inv.customerName ?? 'عميل نقدي'} • ${AppFormat.date(inv.createdAt)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text(
                                  AppFormat.money(inv.grandTotal),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                AppStatus.badge(inv.status),
                                const SizedBox(height: 3),
                                Text(
                                  inv.paymentStatus == 'PAID'
                                      ? 'مدفوعة'
                                      : inv.paymentStatus == 'PARTIAL'
                                          ? 'جزئي (عربون)'
                                          : 'آجل مستحق',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall,
                                ),
                              ],
                            ),
                          ],
                        ),
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


/// بطاقة الملخص: عدد النتائج + إجمالي الصفحة المعروضة.
class _SalesSummary extends StatelessWidget {
  final int total;
  final double pageSum;
  const _SalesSummary({required this.total, required this.pageSum});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: AppColors.actionGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: .3),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الصفحة الحالية',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Color(0xFFDAD6FF))),
                Text(AppFormat.money(pageSum),
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 28,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text('$total',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const Text('فاتورة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Color(0xFFDAD6FF))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
