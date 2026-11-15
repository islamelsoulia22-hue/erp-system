import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../data/shortages_repository.dart';
import '../../domain/shortage.dart';

/// قسم النواقص: طلبات تلقائية بتتسجل عند فواتير البيع
/// (صنف مش موجود أو هينزل تحت الحد الأدنى) — من مورد الصنف.
class ShortagesScreen extends ConsumerStatefulWidget {
  const ShortagesScreen({super.key});

  @override
  ConsumerState<ShortagesScreen> createState() =>
      _ShortagesScreenState();
}

class _ShortagesScreenState
    extends ConsumerState<ShortagesScreen> {
  String? _status = 'PENDING';
  bool _busy = false;
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

  void _selectStatus(String? v) {
    setState(() {
      _status = v;
      _page = 0;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(shortagesPageProvider);
    ref.invalidate(shortagesPendingCountProvider);
  }

  Future<void> _setStatus(Shortage s, String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(shortagesRepositoryProvider)
          .setStatus(s.id, status);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('تم تحديث حالة "${s.productName}".')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر تحديث الحالة.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تحويل النقص لطلب توريد من مورد الصنف، ثم تعليمها ORDERED.
  Future<void> _convertToProcurement(Shortage s) async {
    if (s.productId == null || s.warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'بيانات النقص ناقصة (صنف/مخزن) — لا يمكن التحويل.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(procurementRepositoryProvider);
      final prId = await repo.create(
        supplierId: s.supplierId,
        warehouseId: s.warehouseId!,
        reason: 'طلب تلقائي من النواقص (${s.productName})',
        items: [
          {'product_id': s.productId, 'qty': s.requiredQty},
        ],
      );
      await ref
          .read(shortagesRepositoryProvider)
          .setStatus(s.id, 'ORDERED');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم إنشاء طلب التوريد.')));
        context.push('/procurement/$prId');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر إنشاء طلب التوريد.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) =>
              p.can(Permissions.purchasesCreate) ||
              p.can(Permissions.purchasesEdit),
          orElse: () => false,
        );
    final list = ref.watch(shortagesPageProvider(
        (status: _status, page: _page)));

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          controller: _scroll,
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final f in const [
                    (null, 'الكل'),
                    ('PENDING', 'بانتظار الطلب'),
                    ('ORDERED', 'تم طلبها'),
                    ('DONE', 'تمت'),
                    ('CANCELLED', 'ملغاة'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2),
                      selected: _status == f.$1,
                      onSelected: (_) => _selectStatus(f.$1),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            list.when(
              loading: () =>
                  const LoadingSkeleton(rows: 5),
              error: (e, _) => ErrorState(
                  message: e is AppFailure
                      ? e.messageAr
                      : 'تعذر تحميل النواقص — تأكد من تطبيق ملف الترحيل 0016.'),
              data: (paged) {
                final rows = paged.items;
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon:
                        Icons.inventory_outlined,
                    title: 'لا توجد نواقص',
                    subtitle:
                        'هتتسجل هنا تلقائيا عند بيع صنف رصيده غير كافٍ',
                  );
                }
                return Column(
                  children: [
                    for (final s in rows)
                      _ShortageCard(
                        s: s,
                        busy: _busy,
                        canManage: canManage,
                        onConvert: () =>
                            _convertToProcurement(s),
                        onDone: () =>
                            _setStatus(s, 'DONE'),
                        onCancel: () =>
                            _setStatus(s, 'CANCELLED'),
                      ),
                    AppPagination(
                      page: _page,
                      total: paged.total,
                      onGo: _go,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortageCard extends StatelessWidget {
  final Shortage s;
  final bool busy;
  final bool canManage;
  final VoidCallback onConvert;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  const _ShortageCard({
    required this.s,
    required this.busy,
    required this.canManage,
    required this.onConvert,
    required this.onDone,
    required this.onCancel,
  });

  Color _statusColor() {
    return switch (s.status) {
      'PENDING' => AppColors.warning,
      'ORDERED' => AppColors.info,
      'DONE' => AppColors.success,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.productName,
                    style:
                        theme.textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.15),
                  borderRadius:
                      BorderRadius.circular(8),
                ),
                child: Text(
                    shortageStatusAr(s.status),
                    style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(),
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'المطلوب: ${AppFormat.money(s.requiredQty, suffix: '')} • ${s.warehouseName ?? 'مخزن'}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'المورد: ${s.supplierName ?? 'بدون مورد — حدد موردا عند التحويل'}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            AppFormat.date(s.createdAt),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          if (canManage && s.status == 'PENDING') ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onConvert,
                    icon: const Icon(
                        Icons.request_quote_outlined,
                        size: 18),
                    label:
                        const Text('تحويل لطلب توريد'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDone,
                    child: const Text('تم'),
                  ),
                ),
                const SizedBox(
                    width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                        foregroundColor:
                            AppColors.danger),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
