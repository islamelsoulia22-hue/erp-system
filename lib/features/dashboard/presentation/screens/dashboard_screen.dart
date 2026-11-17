import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_nav.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../products/data/products_repository.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';
import '../../../users/data/users_repository.dart';
import '../providers/dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permsAsync = ref.watch(myPermissionsProvider);
    final profileAsync = ref.watch(myProfileProvider);
    // الصفحات المخفية عن المستخدم الحالي (حددها المدير) —
    // الداشبورد يحترمها زي القائمة تماما.
    final hidden = ref.watch(myHiddenPagesProvider).maybeWhen(
          data: (h) => h,
          orElse: () => const <String>{},
        );

    return permsAsync.when(
      loading: () => const LoadingSkeleton(rows: 8),
      error: (_, _) => const ErrorState(),
      data: (perms) {
        final name = profileAsync.maybeWhen(
          data: (p) =>
              (p?['full_name'] as String?)?.isNotEmpty == true
                  ? p!['full_name'] as String
                  : 'مستخدم',
          orElse: () => 'مستخدم',
        );
        return ResponsiveLayout(
          mobile: ListView(
            padding:
                EdgeInsets.all(context.contentPadding),
            children: [
              _Greeting(name: name),
              const SizedBox(height: AppSpacing.md),
              _KpiGrid(perms: perms, hidden: hidden),
              const SizedBox(height: AppSpacing.mdx),
              _QuickActions(perms: perms, hidden: hidden),
              const SizedBox(height: AppSpacing.mdx),
              // نسخة الجهاز: بدون مركز موافقات (حفظ مباشر).
              if (resolveBackendMode() != BackendMode.local &&
                  ErpNav.approvalsVisible(perms) &&
                  !hidden.contains('/approvals'))
                const _PendingApprovals(),
              if (context.isDesktop)
                const SizedBox(height: AppSpacing.mdx),
              if (context.isDesktop)
                const _ActivityCard()
              else ...[
                const SizedBox(height: AppSpacing.mdx),
                const _ActivityCard(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Greeting extends StatelessWidget {
  final String name;
  const _Greeting({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF0E1330),
            Color(0xFF1A1F6B),
            Color(0xFF4F46FF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46FF).withValues(alpha: .16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -48,
            top: -72,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8B5CF6).withValues(alpha: .20),
              ),
            ),
          ),
          Positioned(
            right: -52,
            bottom: -95,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF14D0A0).withValues(alpha: .12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14D0A0), Color(0xFF38BDF8)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name.characters.first : 'Y',
                    style: const TextStyle(
                      color: Color(0xFF0E1330),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(greet,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFC3C7FF),
                          )),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        AppFormat.weekday(DateTime.now()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFC3C7FF),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .16),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  final PermissionSet perms;
  final Set<String> hidden;
  const _KpiGrid({required this.perms, this.hidden = const {}});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpis = ref.watch(dashboardKpisProvider);
    final daily = ref.watch(dashboardDailyProvider);
    return kpis.when(
      loading: () => const LoadingSkeleton(rows: 3),
      error: (_, _) => const SizedBox.shrink(),
      data: (k) {
        // قيم اليوم — '…' لحد ما تتحمل.
        final d = daily.maybeWhen(
          data: (v) => v,
          orElse: () => null,
        );
        final cards = <Widget>[
          if (perms.can(Permissions.salesView) &&
              !hidden.contains('/sales'))
            KpiCard(
              label: 'مبيعات اليوم',
              value: d == null
                  ? '…'
                  : AppFormat.money(d.salesDay),
              icon: Icons.today_outlined,
              color: AppColors.success,
              containerColor:
                  AppColors.successContainer,
              onTap: () => context.go('/sales'),
            ),
          if (perms.can(Permissions.purchasesView) &&
              !hidden.contains('/purchases'))
            KpiCard(
              label: 'مشتريات اليوم',
              value: d == null
                  ? '…'
                  : AppFormat.money(d.purchasesDay),
              icon: Icons.today_outlined,
              color: AppColors.info,
              containerColor: AppColors.infoContainer,
              onTap: () => context.go('/purchases'),
            ),
          if (perms.can(Permissions.reportsView) &&
              !hidden.contains('/reports'))
            KpiCard(
              label: 'ربح اليوم',
              value: d == null
                  ? '…'
                  : AppFormat.money(d.profitDay),
              icon: Icons.today_outlined,
              color: (d?.profitDay ?? 0) >= 0
                  ? AppColors.success
                  : AppColors.danger,
              containerColor:
                  AppColors.successContainer,
              onTap: () => context.go('/reports'),
            ),
          if (perms.can(Permissions.salesView) &&
              !hidden.contains('/sales'))
            KpiCard(
              label: 'صافي المبيعات',
              value: AppFormat.money(k.salesTotal),
              icon: Icons.trending_up_outlined,
              color: AppColors.success,
              containerColor:
                  AppColors.successContainer,
              onTap: () => context.go('/sales'),
            ),
          if (perms.can(Permissions.purchasesView) &&
              !hidden.contains('/purchases'))
            KpiCard(
              label: 'صافي المشتريات',
              value:
                  AppFormat.money(k.purchasesTotal),
              icon: Icons.trending_down_outlined,
              color: AppColors.info,
              containerColor: AppColors.infoContainer,
              onTap: () => context.go('/purchases'),
            ),
          if (perms.can(Permissions.inventoryView) &&
              !hidden.contains('/inventory'))
            KpiCard(
              label: 'قيمة المخزون (المتاح)',
              value: AppFormat.money(
                  k.inventoryValue),
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
              containerColor:
                  AppColors.primaryContainer,
              onTap: () => context.go('/inventory'),
            ),
          if (perms.can(Permissions.reportsView) &&
              !hidden.contains('/reports'))
            KpiCard(
              label: 'صافي ربح المبيعات (الشهر)',
              value: AppFormat.money(
                  k.netProfitMonth),
              icon: Icons.trending_up_outlined,
              color: k.netProfitMonth >= 0
                  ? AppColors.success
                  : AppColors.danger,
              containerColor:
                  AppColors.successContainer,
              onTap: () => context.go('/reports'),
            ),
          if ((perms.can(Permissions.customersView) ||
                  perms.can(Permissions.salesView)) &&
              !hidden.contains('/customers'))
            KpiCard(
              label: 'مستحقات العملاء',
              value: AppFormat.money(
                  k.customerOutstanding),
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFFB45309),
              containerColor:
                  AppColors.warningContainer,
              onTap: () => context.go('/customers'),
            ),
          if ((perms.can(Permissions.suppliersView) ||
                  perms.can(Permissions.purchasesView)) &&
              !hidden.contains('/suppliers'))
            KpiCard(
              label: 'مستحقات الموردين',
              value: AppFormat.money(
                  k.supplierOutstanding),
              icon: Icons.payments_outlined,
              color: AppColors.purple,
              containerColor:
                  AppColors.purpleContainer,
              onTap: () => context.go('/suppliers'),
            ),
        ];
        if (cards.isEmpty) {
          return const Center(
              child: Text(
                  'لا توجد صلاحيات مفعلة لحسابك بعد.'));
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                context.columns(mobile: 2, tablet: 3, desktop: 5),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisExtent: 92,
          ),
          itemCount: cards.length,
          itemBuilder: (context, i) => cards[i],
        );
      },
    );
  }
}

class _QuickActions extends ConsumerWidget {
  final PermissionSet perms;
  final Set<String> hidden;
  const _QuickActions({required this.perms, this.hidden = const {}});

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !context.mounted) {
      return;
    }
    final product = await ref
        .read(productsRepositoryProvider)
        .findByBarcode(code);
    if (!context.mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'لم يتم العثور على صنف بهذا الباركود'),
          action: SnackBarAction(
            label: 'بحث يدوي',
            onPressed: () => context.push('/products'),
          ),
        ),
      );
      return;
    }
    context.push('/products/${product.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <Widget>[
      if (perms.can(Permissions.salesCreate) &&
          !hidden.contains('/sales'))
        QuickActionButton(
          label: 'فاتورة مبيعات',
          icon: Icons.receipt_long_outlined,
          onTap: () => context.push('/sales/new'),
        ),
      if (perms.can(Permissions.purchasesCreate) &&
          !hidden.contains('/purchases'))
        QuickActionButton(
          label: 'فاتورة مشتريات',
          icon: Icons.shopping_cart_outlined,
          onTap: () =>
              context.push('/purchase-invoices/new'),
        ),
      if (perms.can(Permissions.productsView) &&
          !hidden.contains('/products'))
        QuickActionButton(
          label: 'مسح Barcode',
          icon: Icons.barcode_reader,
          onTap: () => _scan(context, ref),
        ),
      if (perms.can(Permissions.productsCreate) &&
          !hidden.contains('/products'))
        QuickActionButton(
          label: 'إضافة صنف',
          icon: Icons.add_box_outlined,
          onTap: () => context.push('/products/new'),
        ),
      if (perms.can(Permissions.customersCreate) &&
          !hidden.contains('/customers'))
        QuickActionButton(
          label: 'إضافة عميل',
          icon: Icons.person_add_outlined,
          onTap: () => context.push('/customers/new'),
        ),
      if (perms.can(Permissions.suppliersCreate) &&
          !hidden.contains('/suppliers'))
        QuickActionButton(
          label: 'إضافة مورد',
          icon: Icons.handshake_outlined,
          onTap: () => context.push('/suppliers/new'),
        ),
      if (perms.can(Permissions.serialsVerify) &&
          !hidden.contains('/serials/verify'))
        QuickActionButton(
          label: 'تحقق من السيريال',
          icon: Icons.verified_outlined,
          onTap: () => context.push('/serials/verify'),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'إجراءات سريعة'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                context.columns(mobile: 3, tablet: 4, desktop: 6),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisExtent: 100,
          ),
          itemCount: actions.length,
          itemBuilder: (context, i) => actions[i],
        ),
      ],
    );
  }
}

class _PendingApprovals extends ConsumerWidget {
  const _PendingApprovals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalsProvider);
    return pending.when(
      loading: () => const LoadingSkeleton(rows: 3),
      error: (_, _) => const SizedBox.shrink(),
      data: (docs) {
        if (docs.isEmpty) {
          return AppCard(
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Text('لا توجد مستندات بانتظار الموافقة',
                    style:
                        Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        }
        final show = docs.take(5).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'تحتاج إلى موافقة (${docs.length})',
              actionLabel: 'عرض الكل',
              onAction: () =>
                  context.push('/approvals'),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < show.length; i++) ...[
                    ListTile(
                      dense: true,
                      leading: const Icon(
                          Icons.fact_check_outlined,
                          size: 20),
                      title: Text(show[i].number,
                          textDirection:
                              TextDirection.ltr),
                      subtitle: Text(
                          '${show[i].typeAr} • ${show[i].partner ?? ''} • ${AppFormat.money(show[i].amount)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppStatus.badge(
                              'PENDING_APPROVAL'),
                          TextButton(
                            onPressed: () => context
                                .push(show[i].route),
                            child: const Text('فتح'),
                          ),
                        ],
                      ),
                      onTap: () => context
                          .push(show[i].route),
                    ),
                    if (i < show.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String _activityText(String action, String entity) {
  const verbs = {
    'CREATE': 'إنشاء',
    'UPDATE': 'تعديل',
    'APPROVE': 'اعتماد',
    'REJECT': 'رفض',
    'PAYMENT': 'دفعة',
    'RECEIVE': 'استلام',
    'COMPLETE': 'إتمام',
    'STATUS_CHANGE': 'تغيير حالة',
    'STOCK_ADJUSTMENT': 'تسوية مخزون',
    'STOCK_TRANSFER': 'تحويل مخزون',
    'LOGIN': 'تسجيل دخول',
    'LOGOUT': 'تسجيل خروج',
  };
  const entities = {
    'SALES_INVOICE': 'فاتورة مبيعات',
    'PURCHASE_INVOICE': 'فاتورة مشتريات',
    'PURCHASE_ORDER': 'أمر توريد',
    'CUSTOMIZED_ITEM': 'صنف مخصص',
    'MANUFACTURING_ORDER': 'أمر إنتاج',
    'PROCUREMENT_REQUEST': 'طلب توريد',
    'SHIPMENT': 'شحنة',
    'SALES_RETURN': 'مرتجع مبيعات',
    'PURCHASE_RETURN': 'مرتجع مشتريات',
    'PRODUCT': 'منتج',
    'CUSTOMER': 'عميل',
    'SUPPLIER': 'مورد',
    'USER_ROLE': 'دور مستخدم',
    'WAREHOUSE_STOCK': 'مخزون',
    'SESSION': 'جلسة',
  };
  final v = verbs[action.toUpperCase()] ?? action;
  final e = entities[entity.toUpperCase()] ?? '';
  return e.isEmpty ? v : '$v $e';
}

class _ActivityCard extends ConsumerWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider);
    return activity.when(
      loading: () => const LoadingSkeleton(rows: 4),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
                title: 'النشاط الأخير'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0;
                      i < rows.length && i < 6;
                      i++) ...[
                    ListTile(
                      dense: true,
                      leading: const Icon(
                          Icons.history_outlined,
                          size: 20),
                      title: Text(_activityText(
                          '${rows[i]['action'] ?? ''}',
                          '${rows[i]['entity_type'] ?? ''}')),
                      subtitle: rows[i]
                                  ['created_at'] ==
                              null
                          ? null
                          : Text(AppFormat.dateTime(
                              DateTime.tryParse(
                                      '${rows[i]['created_at']}') ??
                                  DateTime.now())),
                    ),
                    if (i < rows.length - 1 &&
                        i < 5)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
