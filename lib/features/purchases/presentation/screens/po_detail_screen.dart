import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../data/purchases_repository.dart';
import '../providers/purchases_providers.dart';

class PurchaseOrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const PurchaseOrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(poDetailProvider(orderId));
    final items = ref.watch(poItemsProvider(orderId));

    return Scaffold(
            body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('حدث خطأ: $e')),
        data: (o) {
          if (o == null) {
            return const Center(child: Text('الأمر غير موجود.'));
          }
          final receivable = o.status == 'ORDERED' ||
              o.status == 'PARTIALLY_RECEIVED';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(o.number,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                  '${o.supplierName ?? 'مورد'} • ${AppStatus.labelOf(o.status)}'),
              const Divider(height: 24),
              const Text('الأصناف',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              items.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => Text('تعذر التحميل: $e'),
                data: (rows) => Column(
                  children: [
                    for (final it in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(it.productName),
                        subtitle: Text(
                            'مطلوب ${it.quantity} • مستلم ${it.received} • متبقي ${it.remaining}'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Text(
                  'الإجمالي: ${o.grandTotal.toStringAsFixed(2)} ج.م',
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (o.status == 'DRAFT')
                FilledButton(
                  onPressed: () => _act(
                      context,
                      ref,
                      () => ref
                          .read(purchasesRepositoryProvider)
                          .submitOrder(o.id)),
                  child: const Text('تأكيد الطلب (ORDERED)'),
                ),
              if (receivable)
                FilledButton.tonal(
                  onPressed: () =>
                      _receiveSheet(context, ref, o.id),
                  child: const Text('استلام بضاعة (جزئي/كلي)'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(poDetailProvider(orderId))
        ..invalidate(poItemsProvider(orderId))
        ..invalidate(poPageProvider);
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

  void _receiveSheet(
      BuildContext context, WidgetRef ref, String id) {
    final ctrls = <String, TextEditingController>{};
    final notes = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder(
        future: ref.read(purchasesRepositoryProvider).orderItems(id),
        builder: (ctx, snap) {
          final rows = snap.data ?? [];
          for (final r in rows) {
            ctrls.putIfAbsent(r.id, () => TextEditingController());
          }
          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'الكميات المستلمة الآن (لا تتجاوز المتبقي)',
                    style:
                        TextStyle(fontWeight: FontWeight.bold)),
                for (final r in rows)
                  TextField(
                    controller: ctrls[r.id],
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                        labelText:
                            '${r.productName} (متبقي ${r.remaining})'),
                  ),
                TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                        labelText: 'ملاحظات الاستلام')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: snap.hasData
                      ? () async {
                          final lines = <Map<String, dynamic>>[];
                          for (final r in rows) {
                            final q = double.tryParse(
                                    ctrls[r.id]!
                                        .text
                                        .trim()) ??
                                0;
                            if (q > 0) {
                              lines.add({
                                'item_id': r.id,
                                'qty': q,
                              });
                            }
                          }
                          if (lines.isEmpty) return;
                          try {
                            await ref
                                .read(purchasesRepositoryProvider)
                                .receive(
                                    id,
                                    lines,
                                    notes.text.trim().isEmpty
                                        ? null
                                        : notes.text.trim());
                            ref
                              ..invalidate(
                                  poDetailProvider(id))
                              ..invalidate(
                                  poItemsProvider(id))
                              ..invalidate(poPageProvider);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx)
                                  .showSnackBar(SnackBar(
                                      content: Text(e
                                              is AppFailure
                                          ? e.messageAr
                                          : 'حدث خطأ — تحقق من الكميات.')));
                            }
                          }
                        }
                      : null,
                  child: const Text('تأكيد الاستلام (يزيد المخزون)'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
