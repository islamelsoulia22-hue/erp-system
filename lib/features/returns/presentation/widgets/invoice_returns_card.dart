import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/returns_repository.dart';

/// مرتجعات فاتورة مبيعات — بتسمع في الفاتورة الأساسية:
/// المرتجع المعتمد بيرجع المخزون تلقائيا، وهنا بيظهر
/// إجمالي المرتجع من كل صنف عشان المرتجع التاني يبقى على الباقي بس.
class SalesInvoiceReturnsCard extends ConsumerWidget {
  final String invoiceId;
  const SalesInvoiceReturnsCard({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .read(returnsRepositoryProvider)
          .salesReturnsOf(invoiceId),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const SizedBox.shrink();
        final done = rows.where((r) => r.status == 'COMPLETED');
        final doneTotal =
            done.fold(0.0, (s, r) => s + r.total);
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'مرتجعات الفاتورة'),
              _InfoLine(
                  label: 'إجمالي المرتجع المعتمد',
                  value: AppFormat.money(doneTotal)),
              const SizedBox(height: 4),
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.number,
                      textDirection: TextDirection.ltr),
                  subtitle: Text(
                      '${AppStatus.labelOf(r.status)} • ${AppFormat.money(r.total)}'),
                  trailing: AppStatus.badge(r.status),
                  onTap: () =>
                      context.push('/sales-returns/${r.id}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// مرتجعات فاتورة مشتريات — نفس الفكرة للمورد.
class PurchaseInvoiceReturnsCard extends ConsumerWidget {
  final String invoiceId;
  const PurchaseInvoiceReturnsCard(
      {super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .read(returnsRepositoryProvider)
          .purchaseReturnsOf(invoiceId),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const SizedBox.shrink();
        final done = rows.where((r) => r.status == 'COMPLETED');
        final doneTotal =
            done.fold(0.0, (s, r) => s + r.total);
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'مرتجعات الفاتورة'),
              _InfoLine(
                  label: 'إجمالي المرتجع المعتمد',
                  value: AppFormat.money(doneTotal)),
              const SizedBox(height: 4),
              for (final r in rows)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.number,
                      textDirection: TextDirection.ltr),
                  subtitle: Text(
                      '${AppStatus.labelOf(r.status)} • ${AppFormat.money(r.total)}'),
                  trailing: AppStatus.badge(r.status),
                  onTap: () => context.push(
                      '/purchase-returns/${r.id}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium)),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
