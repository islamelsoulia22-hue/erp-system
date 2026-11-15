import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/customer.dart';
import '../providers/customers_providers.dart';

/// Customers: toolbar (search + new action), table on desktop,
/// compact cards on mobile. Pagination logic unchanged.
class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() =>
      _CustomersListScreenState();
}

class _CustomersListScreenState
    extends ConsumerState<CustomersListScreen> {
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

  void _submitSearch(String v) {
    ref.read(customerSearchProvider.notifier).state = v;
    setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.customersCreate),
          orElse: () => false,
        );
    final page = ref.watch(customersPageProvider(_page));
    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(customersPageProvider(_page).future),
        child: ListView(
          controller: _scroll,
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _search,
                      hint:
                          'بحث بالاسم أو الهاتف أو الكود',
                      onSubmitted: _submitSearch,
                      onClear: () => _submitSearch(''),
                    ),
                  ),
                  if (canCreate) ...[
                    const SizedBox(
                        width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push('/customers/new'),
                      icon: const Icon(
                          Icons.add_outlined,
                          size: 18),
                      label: const Text('عميل'),
                    ),
                  ],
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
                    icon: Icons.people_outline,
                    title: 'لا يوجد عملاء',
                    subtitle: 'أضف أول عميل',
                  )
                else
                  ResponsiveTable<Customer>(
                columns: [
                  TableColumn(
                      label: 'العميل',
                      value: (c) => c.name),
                  TableColumn(
                      label: 'الكود',
                      value: (c) => c.code),
                  TableColumn(
                      label: 'الهاتف',
                      value: (c) => c.phone ?? '—'),
                  TableColumn(
                      label: 'الحالة',
                      value: (c) => c.isActive
                          ? 'نشط'
                          : 'موقوف'),
                ],
                rows: paged.items,
                onTap: (c) =>
                    context.push('/customers/${c.id}'),
                cardBuilder: (c) => AppCard(
                  onTap: () => context
                      .push('/customers/${c.id}'),
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                          radius: 18,
                          child: Text(c.name.isNotEmpty
                              ? c.name[0]
                              : '?')),
                      const SizedBox(
                          width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow
                                    .ellipsis),
                            Text(
                              '${c.code}${c.phone != null ? ' • ${c.phone}' : ''}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                              textDirection:
                                  TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                      if (!c.isActive)
                        AppStatus.badge('INACTIVE'),
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
