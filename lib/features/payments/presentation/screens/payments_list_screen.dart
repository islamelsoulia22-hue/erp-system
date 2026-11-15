import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/payments_repository.dart';

class PaymentsListScreen extends ConsumerStatefulWidget {
  const PaymentsListScreen({super.key});
  @override
  ConsumerState<PaymentsListScreen> createState() =>
      _PaymentsListScreenState();
}

class _PaymentsListScreenState
    extends ConsumerState<PaymentsListScreen> {
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
          data: (p) =>
              p.can(Permissions.salesCreate) ||
              p.can(Permissions.purchasesCreate),
          orElse: () => false,
        );
    final page = ref.watch(paymentsPageProvider(_page));
    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () =>
                  context.push('/payments/new'),
              child: const Icon(Icons.add_outlined))
          : null,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(paymentsPageProvider(_page).future),
        child: page.when(
          loading: () => ListView(children: const [
            SizedBox(height: 80),
            Center(child: CircularProgressIndicator()),
          ]),
          error: (e, _) => ListView(children: const [
            SizedBox(height: 80),
            Center(
                child: Text(
                    'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.')),
          ]),
          data: (paged) => paged.items.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Center(child: Text('لا توجد مدفوعات'))
                ])
              : ListView.separated(
                  controller: _scroll,
                  itemCount: paged.items.length + 1,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= paged.items.length) {
                      return AppPagination(
                        page: _page,
                        total: paged.total,
                        onGo: _go,
                      );
                    }
                    final p = paged.items[i];
                    final isIn =
                        p.salesInvoiceId != null;
                    final invRoute =
                        p.salesInvoiceId != null
                            ? '/sales/${p.salesInvoiceId}'
                            : p.purchaseInvoiceId != null
                                ? '/purchase-invoices/${p.purchaseInvoiceId}'
                                : null;
                    final sub = [
                      AppFormat.date(p.date),
                      if ((p.partnerName ?? '')
                          .isNotEmpty)
                        p.partnerName!,
                      if ((p.invoiceNumber ?? '')
                          .isNotEmpty)
                        'فاتورة ${p.invoiceNumber}',
                      if ((p.methodCode ?? '')
                          .isNotEmpty)
                        p.methodCode!,
                      if ((p.reference ?? '')
                          .isNotEmpty)
                        p.reference!,
                    ].join(' • ');
                    return AppCard(
                      onTap: invRoute == null
                          ? null
                          : () =>
                                context.push(invRoute),
                      padding: const EdgeInsets.all(
                          AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(
                              isIn
                                  ? Icons
                                      .arrow_downward_outlined
                                  : Icons
                                      .arrow_upward_outlined,
                              color: isIn
                                  ? Colors.green
                                  : Colors.orange,
                              size: 22),
                          const SizedBox(
                              width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(p.number,
                                    textDirection:
                                        TextDirection.ltr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                Text(sub,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow
                                        .ellipsis),
                                Text(
                                    AppFormat.money(
                                        p.amount),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge),
                              ],
                            ),
                          ),
                          AppStatus.badge(p.status),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
