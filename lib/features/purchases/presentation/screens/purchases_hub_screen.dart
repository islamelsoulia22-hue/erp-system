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
import '../../domain/purchases.dart';
import '../providers/purchases_providers.dart';

/// Purchases hub: orders + invoices tabs with dense tables,
/// status badges and inline create actions. Numbered pagination (10/page).
class PurchasesHubScreen extends ConsumerWidget {
  const PurchasesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'الفواتير'),
                Tab(text: 'أوامر التوريد'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_InvoicesTab(), _OrdersTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersTab extends ConsumerStatefulWidget {
  const _OrdersTab();
  @override
  ConsumerState<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<_OrdersTab> {
  final _scroll = ScrollController();
  int _page = 0;


  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.purchasesCreate),
          orElse: () => false,
        );
    final page = ref.watch(poPageProvider(_page));
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(poPageProvider(_page).future),
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          if (canCreate)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/purchase-orders/new'),
                icon: const Icon(Icons.add_outlined,
                    size: 18),
                label: const Text('أمر توريد'),
              ),
            ),
          if (canCreate)
            const SizedBox(height: AppSpacing.md),
          ...page.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.mdx),
                child: Center(
                    child: CircularProgressIndicator()),
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
                  icon: Icons.shopping_cart_outlined,
                  title: 'لا توجد أوامر',
                  subtitle: 'أنشئ أول أمر توريد',
                )
              else
                ResponsiveTable<PurchaseOrder>(
                  columns: [
                    TableColumn(
                        label: 'الأمر',
                        value: (o) => o.number),
                    TableColumn(
                        label: 'المورد',
                        value: (o) =>
                            o.supplierName ?? 'مورد'),
                    TableColumn(
                        label: 'الحالة',
                        value: (o) =>
                            AppStatus.labelOf(o.status)),
                    TableColumn(
                        label: 'الإجمالي',
                        numeric: true,
                        value: (o) => AppFormat.money(
                            o.grandTotal,
                            suffix: '')),
                    TableColumn(
                        label: 'التاريخ',
                        value: (o) =>
                            AppFormat.date(o.createdAt)),
                  ],
                  rows: paged.items,
                  onTap: (o) => context
                      .push('/purchase-orders/${o.id}'),
                  cardBuilder: (o) => AppCard(
                    onTap: () => context.push(
                        '/purchase-orders/${o.id}'),
                    padding: const EdgeInsets.all(
                        AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(o.number,
                                  textDirection:
                                      TextDirection.ltr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                              Text(
                                '${o.supplierName ?? 'مورد'} • ${AppFormat.date(o.createdAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                              Text(
                                  AppFormat.money(
                                      o.grandTotal),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge),
                            ],
                          ),
                        ),
                        AppStatus.badge(o.status),
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
    );
  }
}

class _InvoicesTab extends ConsumerStatefulWidget {
  const _InvoicesTab();
  @override
  ConsumerState<_InvoicesTab> createState() =>
      _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> {
  final _scroll = ScrollController();
  int _page = 0;


  @override
  void dispose() {
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
          data: (p) => p.can(Permissions.purchasesCreate),
          orElse: () => false,
        );
    final from = ref.watch(piFromDateProvider);
    final to = ref.watch(piToDateProvider);
    final page = ref.watch(piPageProvider(_page));
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(piPageProvider(_page).future),
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          AppCard(
            child: DateFilterRow(
              from: from,
              to: to,
              onFrom: (v) {
                ref
                    .read(piFromDateProvider.notifier)
                    .state = v;
                _resetPage();
              },
              onTo: (v) {
                ref
                    .read(piToDateProvider.notifier)
                    .state = v;
                _resetPage();
              },
              onClear: () {
                ref
                    .read(piFromDateProvider.notifier)
                    .state = null;
                ref
                    .read(piToDateProvider.notifier)
                    .state = null;
                _resetPage();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (canCreate)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: () =>
                    context.push('/purchase-invoices/new'),
                icon: const Icon(Icons.add_outlined,
                    size: 18),
                label: const Text('فاتورة مشتريات'),
              ),
            ),
          if (canCreate)
            const SizedBox(height: AppSpacing.md),
          ...page.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.mdx),
                child: Center(
                    child: CircularProgressIndicator()),
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
                  subtitle: 'أنشئ أول فاتورة مشتريات',
                )
              else
                ResponsiveTable<PurchaseInvoice>(
                  columns: [
                    TableColumn(
                        label: 'الفاتورة',
                        value: (v) => v.number),
                    TableColumn(
                        label: 'المورد',
                        value: (v) =>
                            v.supplierName ?? 'مورد'),
                    TableColumn(
                        label: 'الحالة',
                        value: (v) => AppStatus.labelOf(
                            v.status)),
                    TableColumn(
                        label: 'الإجمالي',
                        numeric: true,
                        value: (v) => AppFormat.money(
                            v.grandTotal,
                            suffix: '')),
                    TableColumn(
                        label: 'التاريخ',
                        value: (v) =>
                            AppFormat.date(v.createdAt)),
                  ],
                  rows: paged.items,
                  onTap: (v) => context.push(
                      '/purchase-invoices/${v.id}'),
                  cardBuilder: (v) => AppCard(
                    onTap: () => context.push(
                        '/purchase-invoices/${v.id}'),
                    padding: const EdgeInsets.all(
                        AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(v.number,
                                  textDirection:
                                      TextDirection.ltr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                              Text(
                                '${v.supplierName ?? 'مورد'} • ${AppFormat.date(v.createdAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                              Text(
                                  AppFormat.money(
                                      v.grandTotal),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge),
                            ],
                          ),
                        ),
                        AppStatus.badge(v.status),
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
    );
  }
}
