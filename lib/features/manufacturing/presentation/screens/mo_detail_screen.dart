import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/customized_from_invoice.dart';
import '../../data/manufacturing_repository.dart';
import '../providers/manufacturing_providers.dart';
import 'manufacturing_hub_screen.dart' show moStatusAr;

class ManufacturingOrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const ManufacturingOrderDetailScreen(
      {super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(moDetailProvider(orderId));
    final mats = ref.watch(moMaterialsProvider(orderId));
    final canMake = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.inventoryAdjust),
          orElse: () => false,
        );

    return Scaffold(
            body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('حدث خطأ: $e')),
        data: (o) {
          if (o == null) {
            return const Center(child: Text('الأمر غير موجود.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(o.number,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(moStatusAr(o.status)),
              if (o.customizedId != null) ...[
                const SizedBox(height: 8),
                _CustomizedSourceCard(czId: o.customizedId!),
              ],
              const Divider(height: 24),
              const Text('الخامات',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              mats.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => Text('تعذر التحميل: $e'),
                data: (rows) => Column(
                  children: [
                    for (final m in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            m.productName ?? 'خامة'),
                        subtitle: Text(
                            'مطلوب ${m.requiredQty} • مستهلك ${m.consumedQty}'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (o.status == 'DRAFT' && canMake)
                FilledButton(
                  onPressed: () => _act(
                      context,
                      ref,
                      () => ref
                          .read(manufacturingRepositoryProvider)
                          .start(o.id)),
                  child: const Text(
                      'بدء التصنيع (خصم الخامات)'),
                ),
              if (o.status == 'IN_PROGRESS' && canMake)
                FilledButton(
                  onPressed: () => _complete(
                      context, ref, o.id, o.number),
                  child: const Text(
                      'إتمام التصنيع (إضافة التام)'),
                ),
              if (!canMake)
                const Text(
                    'البدء والإتمام يتطلبان صلاحية تسوية المخزون.',
                    textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref,      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(moDetailProvider(orderId))
        ..invalidate(moMaterialsProvider(orderId))
        ..invalidate(moPageProvider);
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
                : 'حدث خطأ — تحقق من رصيد الخامات.')));
      }
    }
  }

  /// إتمام التصنيع + إشعار فريق المبيعات أن الطلب جاهز للصرف.
  Future<void> _complete(BuildContext context, WidgetRef ref,
      String id, String number) async {
    try {
      await ref
          .read(manufacturingRepositoryProvider)
          .complete(id);
      await notifySalesTeam(
        ref,
        title: 'طلب تصنيع جاهز للصرف',
        message: 'أمر التصنيع $number اكتمل — يمكن الصرف والتسليم.',
        entityType: 'MANUFACTURING_ORDER',
        entityId: id,
      );
      ref
        ..invalidate(moDetailProvider(orderId))
        ..invalidate(moMaterialsProvider(orderId))
        ..invalidate(moPageProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم الإتمام وإشعار المبيعات.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ — تحقق من رصيد الخامات.')));
      }
    }
  }
}

/// كارت الصنف المخصص مصدر الأمر (مع مواصفاته).
class _CustomizedSourceCard extends ConsumerWidget {
  final String czId;
  const _CustomizedSourceCard({required this.czId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cz = ref.watch(czDetailProvider(czId));
    return cz.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (c) {
        if (c == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🔧 ${c.name} (${c.code})',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall),
              if (c.specSummary.isNotEmpty)
                Text(c.specSummary,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall),
            ],
          ),
        );
      },
    );
  }
}
