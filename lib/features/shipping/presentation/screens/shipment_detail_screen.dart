import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../data/shipping_repository.dart';
import 'shipments_list_screen.dart' show shipStatusAr;

class ShipmentDetailScreen extends ConsumerWidget {
  final String shipmentId;
  const ShipmentDetailScreen(
      {super.key, required this.shipmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(shipmentDetailProvider(shipmentId));

    return Scaffold(
            body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('حدث خطأ: $e')),
        data: (s) {
          if (s == null) {
            return const Center(child: Text('الشحنة غير موجودة.'));
          }
          return FutureBuilder(
            future: ref
                .read(shippingRepositoryProvider)
                .getRaw(s.id),
            builder: (context, snap) {
              final raw = snap.data;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.number,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(
                      '${s.invoiceNumber ?? ''} • ${shipStatusAr(s.status)}'),
                  const Divider(height: 24),
                  _row('المستلم', s.recipient ?? '—'),
                  _row('الهاتف', s.phone ?? '—'),
                  _row('المدينة', s.city ?? '—'),
                  _row('العنوان', (raw?['address'] as String?) ?? '—'),
                  _row('التتبع',
                      (raw?['tracking_number'] as String?) ?? '—'),
                  const SizedBox(height: 12),
                  if (s.status == 'PREPARING')
                    FilledButton(
                      onPressed: () => _act(
                          context,
                          ref,
                          () => ref
                              .read(shippingRepositoryProvider)
                              .ship(s.id)),
                      child: const Text(
                          'شحن (خصم المخزون المحجوز)'),
                    ),
                  if (s.status == 'SHIPPED')
                    FilledButton.tonal(
                      onPressed: () => _act(
                          context,
                          ref,
                          () => ref
                              .read(shippingRepositoryProvider)
                              .deliver(s.id)),
                      child: const Text('تأكيد التوصيل'),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(k)),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(shipmentDetailProvider(shipmentId))
        ..invalidate(shipmentsPageProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم تنفيذ العملية بنجاح.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ — تحقق من اعتماد الفاتورة والرصيد.')));
      }
    }
  }
}
