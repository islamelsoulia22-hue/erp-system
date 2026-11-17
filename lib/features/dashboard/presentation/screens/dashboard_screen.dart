import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../../core/widgets/yad_widgets.dart';
import '../../../procurement/data/procurement_repository.dart' show unreadCountProvider;
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
        final showApprovals =
            resolveBackendMode() != BackendMode.local &&
                ErpNav.approvalsVisible(perms) &&
                !hidden.contains('/approvals');
        if (context.isMobile) {
          return _MobileHome(
            name: name,
            perms: perms,
            hidden: hidden,
            showApprovals: showApprovals,
          );
        }
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
              if (showApprovals) const _PendingApprovals(),
              const SizedBox(height: AppSpacing.mdx),
              const _ActivityCard(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$greet، $name',
            style: theme.textTheme.headlineSmall),
        Text(AppFormat.weekday(DateTime.now()),
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  final PermissionSet perms;
  final Set<String> hidden;
  /// لو محددة: تُعرض هذه البطاقات فقط (الموبايل = 4 بطاقات التصميم).
  final Set<String>? onlyLabels;
  const _KpiGrid(
      {required this.perms, this.hidden = const {}, this.onlyLabels});

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
        final allCards = <KpiCard>[
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
        final cards = allCards
            .where((c) =>
                onlyLabels == null || onlyLabels!.contains(c.label))
            .toList();
        if (cards.isEmpty && onlyLabels != null) {
          return const SizedBox.shrink();
        }
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
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 128,
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
    final raw = <QuickActionButton>[
      if (perms.can(Permissions.salesCreate) &&
          !hidden.contains('/sales'))
        QuickActionButton(
          label: 'فاتورة بيع',
          icon: Icons.receipt_long_outlined,
          onTap: () => context.push('/sales/new'),
        ),
      if (perms.can(Permissions.purchasesCreate) &&
          !hidden.contains('/purchases'))
        QuickActionButton(
          label: 'فاتورة شراء',
          icon: Icons.shopping_cart_outlined,
          onTap: () =>
              context.push('/purchase-invoices/new'),
        ),
      if (perms.can(Permissions.productsCreate) &&
          !hidden.contains('/products'))
        QuickActionButton(
          label: 'صنف جديد',
          icon: Icons.sell_outlined,
          onTap: () => context.push('/products/new'),
        ),
      if (perms.can(Permissions.productsView) &&
          !hidden.contains('/products'))
        QuickActionButton(
          label: 'مسح باركود',
          icon: Icons.qr_code_scanner_outlined,
          onTap: () => _scan(context, ref),
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
    if (raw.isEmpty) return const SizedBox.shrink();
    const tints = [
      AppColors.indigoDeep,
      AppColors.indigoDeep,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
      AppColors.purple,
      AppColors.danger,
    ];
    // الموبايل: 4 إجراءات فقط زي التصميم (الباقي من شاشة "المزيد").
    final shown = context.isMobile ? raw.take(4).toList() : raw;
    final actions = <Widget>[
      for (var i = 0; i < shown.length; i++)
        shown[i].styled(primary: i == 0, tint: tints[i % tints.length]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!context.isMobile)
          const SectionHeader(title: 'إجراءات سريعة'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                context.columns(mobile: 4, tablet: 5, desktop: 7),
            mainAxisSpacing: 12,
            crossAxisSpacing: 6,
            mainAxisExtent: 104,
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
          return GestureDetector(
            onTap: () => context.push('/approvals'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.successContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.success, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('لا توجد مستندات بانتظار الموافقة',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      leading: _activityTile(
                          '${rows[i]['action'] ?? ''}'),
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


Widget _activityTile(String action) {
  switch (action.toUpperCase()) {
    case 'LOGIN':
      return const YadIconTile(
          icon: Icons.login_outlined,
          color: AppColors.success,
          background: AppColors.successContainer,
          size: 40,
          radius: 14);
    case 'LOGOUT':
      return const YadIconTile(
          icon: Icons.logout_outlined,
          color: AppColors.danger,
          background: AppColors.dangerContainer,
          size: 40,
          radius: 14);
    case 'APPROVE':
      return const YadIconTile(
          icon: Icons.task_alt_outlined,
          color: AppColors.success,
          background: AppColors.successContainer,
          size: 40,
          radius: 14);
    case 'REJECT':
      return const YadIconTile(
          icon: Icons.cancel_outlined,
          color: AppColors.danger,
          background: AppColors.dangerContainer,
          size: 40,
          radius: 14);
    default:
      return const YadIconTile(
          icon: Icons.history_outlined,
          color: AppColors.indigoDeep,
          background: AppColors.primaryContainer,
          size: 40,
          radius: 14);
  }
}

/// الرئيسية على الموبايل: هيرو داكن بالمبيعات + بطاقات تتداخل معه
/// + إجراءات سريعة + حالة الموافقات + النشاط الأخير.
class _MobileHome extends ConsumerWidget {
  final String name;
  final PermissionSet perms;
  final Set<String> hidden;
  final bool showApprovals;
  const _MobileHome({
    required this.name,
    required this.perms,
    required this.hidden,
    required this.showApprovals,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final heroH = top + 318;
    final canSales = perms.can(Permissions.salesView) &&
        !hidden.contains('/sales');
    final kpis = ref.watch(dashboardKpisProvider).maybeWhen(
          data: (k) => k,
          orElse: () => null,
        );
    final daily = ref.watch(dashboardDailyProvider).maybeWhen(
          data: (d) => d,
          orElse: () => null,
        );
    final unread = ref.watch(unreadCountProvider).maybeWhen(
          data: (n) => n,
          orElse: () => 0,
        );
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final initial = name.isNotEmpty ? name.characters.first : 'م';
    const soft = AppColors.heroSoft;

    Widget heroBtn(IconData icon, String label, VoidCallback onTap,
        {int badge = 0}) {
      return TapScale(
        onTap: onTap,
        semanticLabel: label,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: Colors.white.withValues(alpha: .18)),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            if (badge > 0)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: IgnorePointer(child: PulseBadge(count: badge)),
              ),
          ],
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListView(
      padding: EdgeInsets.zero,
      children: [
        Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(40)),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                      gradient: AppColors.heroGradient),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -70,
                        left: -50,
                        child: Floating(
                          period: const Duration(seconds: 7),
                          child: Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              AppColors.violet.withValues(alpha: .55),
                              AppColors.violet.withValues(alpha: 0),
                            ], stops: const [0, .7]),
                          ),
                        ),
                        ),
                      ),
                      Positioned(
                        bottom: -90,
                        right: -40,
                        child: Floating(
                          period: const Duration(seconds: 9),
                          child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              AppColors.mint.withValues(alpha: .35),
                              AppColors.mint.withValues(alpha: 0),
                            ], stops: const [0, .7]),
                          ),
                        ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (canSales)
              Positioned(
                top: top + 108,
                left: 16,
                child: const HeroSparkline(),
              ),
            Positioned(
              top: top + 22,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.mint, AppColors.sky]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(initial,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.midnight)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greet,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: soft)),
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 20,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                      heroBtn(Icons.refresh_outlined, 'تحديث', () {
                        ref
                          ..invalidate(dashboardKpisProvider)
                          ..invalidate(dashboardDailyProvider)
                          ..invalidate(recentActivityProvider)
                          ..invalidate(pendingApprovalsProvider)
                          ..invalidate(myPermissionsProvider)
                          ..invalidate(myHiddenPagesProvider)
                          ..invalidate(myProfileProvider);
                      }),
                      const SizedBox(width: 10),
                      heroBtn(Icons.notifications_none_outlined,
                          'الإشعارات', () => context.push('/notifications'),
                          badge: unread),
                    ],
                  ),
                  if (canSales) ...[
                    const SizedBox(height: 26),
                    const Text('صافي المبيعات',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: soft)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              kpis == null
                                  ? '…'
                                  : AppFormat.money(kpis.salesTotal,
                                      suffix: ''),
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 50,
                                  height: 1.1,
                                  letterSpacing: -1,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('ج.م',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: soft)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (perms.can(Permissions.reportsView))
                          _HeroPill(
                            'ربح الشهر ${kpis == null ? '…' : AppFormat.money(kpis.netProfitMonth)}',
                            bg: AppColors.mint.withValues(alpha: .18),
                            fg: const Color(0xFF5BF0C8),
                          ),
                        _HeroPill(
                          'اليوم ${daily == null ? '…' : AppFormat.money(daily.salesDay)}',
                          bg: Colors.white.withValues(alpha: .12),
                          fg: const Color(0xFFE4E6FF),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, heroH - 62, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RiseIn(
                    index: 1,
                    child: _KpiGrid(
                      perms: perms,
                      hidden: hidden,
                      onlyLabels: canSales
                          ? const {
                              'صافي المشتريات',
                              'قيمة المخزون (المتاح)',
                              'صافي ربح المبيعات (الشهر)',
                              'مستحقات الموردين',
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 22),
                  RiseIn(
                    index: 2,
                    child: _QuickActions(perms: perms, hidden: hidden),
                  ),
                  if (showApprovals) ...[
                    const SizedBox(height: 22),
                    RiseIn(index: 3, child: const _PendingApprovals()),
                  ],
                  const SizedBox(height: 24),
                  RiseIn(index: 4, child: const _ActivityCard()),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _HeroPill(this.text, {required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg)),
    );
  }
}
