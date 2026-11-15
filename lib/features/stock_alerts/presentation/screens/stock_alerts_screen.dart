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
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../data/stock_alerts_repository.dart';

/// تنبيهات المخزون للمدير:
/// حد أدنى → طلب بضاعة (يعمل طلب توريد أو يقول عارف تمام)،
/// نفاذ → متسجل في النواقص تلقائيا + إشعار.
class StockAlertsScreen extends ConsumerStatefulWidget {
  const StockAlertsScreen({super.key});

  @override
  ConsumerState<StockAlertsScreen> createState() =>
      _StockAlertsScreenState();
}

class _StockAlertsScreenState
    extends ConsumerState<StockAlertsScreen> {
  String? _status = 'NEW';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(stockAlertsProvider(_status));
    final canManage =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) =>
                  p.can(Permissions.purchasesApprove) ||
                  p.can(Permissions.usersManage),
              orElse: () => false,
            );
    return ResponsiveLayout(
      mobile: ListView(
        padding: EdgeInsets.all(context.contentPadding),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in const [
                  (null, 'الكل'),
                  ('NEW', 'جديدة'),
                  ('ACK', 'تم العلم'),
                  ('RESOLVED', 'اتحلت'),
                ])
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.only(
                            end: 6),
                    child: ChoiceChip(
                      label: Text(e.$2),
                      selected: _status == e.$1,
                      visualDensity:
                          VisualDensity.compact,
                      onSelected: (_) => setState(
                          () => _status = e.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          alerts.when(
            loading: () =>
                const LoadingSkeleton(rows: 4),
            error: (_, _) => const ErrorState(
                message: 'تعذر تحميل التنبيهات.'),
            data: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons
                      .notifications_active_outlined,
                  title: 'لا توجد تنبيهات',
                  subtitle:
                      'أول ما صنف يوصل للحد الأدنى أو ينفذ هيظهر هنا.',
                );
              }
              return Column(
                children: [
                  for (final a in rows)
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppSpacing.sm),
                      child: _AlertCard(
                        alert: a,
                        canManage: canManage,
                        busy: _busy,
                        onAck: () => _ack(a.id),
                        onOrder: () =>
                            _orderSupply(a),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(stockAlertsProvider(_status));
    ref.invalidate(stockAlertsNewCountProvider);
  }

  Future<void> _ack(String id) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(stockAlertsRepositoryProvider)
          .acknowledge(id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تمام — اتسجل إنك عارف.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر الإقرار.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// طلب توريد بالكمية الناقصة (الحد الأدنى − المتاح).
  Future<void> _orderSupply(StockAlert a) async {
    if (a.warehouseId == null ||
        a.productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'تعذر تحديد الصنف أو المخزن.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final stock = await ref
          .read(warehousesRepositoryProvider)
          .stockOf(a.warehouseId!);
      var avail = a.availableAtAlert;
      for (final s in stock) {
        if (s.productId == a.productId) {
          avail = s.available;
          break;
        }
      }
      final qty =
          (a.minimumStock - avail).clamp(1, 1e9).toDouble();
      final prId = await ref
          .read(procurementRepositoryProvider)
          .create(
            supplierId: a.supplierId,
            warehouseId: a.warehouseId!,
            reason:
                'طلب تلقائي من تنبيه مخزون (${a.productName})',
            items: [
              {'product_id': a.productId, 'qty': qty}
            ],
          );
      try {
        await ref
            .read(procurementRepositoryProvider)
            .submit(prId);
      } catch (_) {}
      await ref
          .read(stockAlertsRepositoryProvider)
          .acknowledge(a.id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'اتعمل طلب توريد بـ $qty وراح للاعتماد.')));
      context.push('/procurement/$prId');
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
}

class _AlertCard extends StatelessWidget {
  final StockAlert alert;
  final bool canManage;
  final bool busy;
  final VoidCallback onAck;
  final VoidCallback onOrder;
  const _AlertCard({
    required this.alert,
    required this.canManage,
    required this.busy,
    required this.onAck,
    required this.onOrder,
  });

  @override
  Widget build(BuildContext context) {
    final out = alert.isOut;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(alert.productName,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis),
              ),
              AppStatus.badge(alert.status),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(
                label: Text(out
                    ? 'نفذ من المخزون'
                    : 'وصل للحد الأدنى'),
                backgroundColor: out
                    ? AppColors.dangerContainer
                    : AppColors.warningContainer,
                visualDensity:
                    VisualDensity.compact,
              ),
              Chip(
                label: Text(
                    '${alert.warehouseName} • متاح ${AppFormat.money(alert.availableAtAlert, suffix: '')} / حد ${AppFormat.money(alert.minimumStock, suffix: '')}'),
                visualDensity:
                    VisualDensity.compact,
              ),
            ],
          ),
          Text(
            AppFormat.dateTime(alert.createdAt),
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
          if (out)
            const Text(
              'اتسجل في النواقص تلقائيا.',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey),
            ),
          if (alert.isNew && canManage) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        busy ? null : onOrder,
                    icon: const Icon(
                        Icons
                            .local_shipping_outlined,
                        size: 18),
                    label:
                        const Text('طلب توريد'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        busy ? null : onAck,
                    child: const Text(
                        'عارف، تمام'),
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
