import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/attachments/widgets/attachments_section.dart';
import '../../../../core/errors/failures.dart';
import '../../data/returns_repository.dart';

class SalesReturnDetailScreen extends ConsumerWidget {
  final String returnId;
  const SalesReturnDetailScreen(
      {super.key, required this.returnId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
            body: FutureBuilder(
        future: ref
            .read(returnsRepositoryProvider)
            .getSales(returnId),
        builder: (context, snap) {
          final r = snap.data;
          if (snap.connectionState ==
              ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator());
          }
          if (r == null) {
            return const Center(
                child: Text('المرتجع غير موجود.'));
          }
          return FutureBuilder(
            future: ref
                .read(returnsRepositoryProvider)
                .salesItems(returnId),
            builder: (context, itemsSnap) {
              final items = itemsSnap.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(r.number,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(
                      '${r.partner ?? ''} • ${r.status} • ${r.total.toStringAsFixed(2)}'),
                  const Divider(height: 24),
                  for (final it in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(it.name),
                      subtitle: Text(
                          '${it.qty} × ${it.price} = ${it.total.toStringAsFixed(2)}'),
                    ),
                  const Divider(height: 24),
                  if (r.status == 'DRAFT')
                    FilledButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(returnsRepositoryProvider)
                              .completeSales(r.id);
                          ref.invalidate(
                              salesReturnsPageProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content: Text(
                                        'تم اعتماد المرتجع وزيادة المخزون.')));
                            Navigator.of(context).pop();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(e
                                            is AppFailure
                                        ? e.messageAr
                                        : 'حدث خطأ — تحقق من الكميات.')));
                          }
                        }
                      },
                      child: const Text(
                          'اعتماد (زيادة المخزون وتخفيض المستحق)'),
                    ),
                  AttachmentsSection(
                      entityType: 'SALES_RETURN',
                      entityId: r.id),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
