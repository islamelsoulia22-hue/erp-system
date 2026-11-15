import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_auth.dart';
import 'local_inventory_screens.dart';
import 'local_login_screen.dart';
import 'local_partners.dart';
import 'local_partners_screens.dart';
import 'local_payments.dart';
import 'local_payments_screens.dart';
import 'local_products.dart';
import 'local_products_screens.dart';
import 'local_purchases.dart';
import 'local_purchases_screens.dart';
import 'local_reports.dart';
import 'local_sales.dart';
import 'local_sales_screens.dart';
import 'local_warehouses.dart';

/// بوابة اللوكال: دخول لو مفيش جلسة، الرئيسية لو فيه.
class LocalGate extends ConsumerWidget {
  const LocalGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(localSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('تعذر قراءة الجلسة.'))),
      data: (user) =>
          user == null ? const LocalLoginScreen() : LocalHomeScreen(user: user),
    );
  }
}

/// رئيسية اللوكال: مؤشرات اليوم والإجماليات + الوحدات.
class LocalHomeScreen extends ConsumerWidget {
  final LocalUser user;
  const LocalHomeScreen({super.key, required this.user});

  Future<void> _logout(WidgetRef ref) async {
    await ref.read(localAuthRepositoryProvider).logout();
    ref.invalidate(localSessionProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(localTotalsProvider);
    final daily = ref.watch(localDailyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('أهلا ${user.fullName}'),
        actions: [
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => _logout(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(localTotalsProvider);
          ref.invalidate(localDailyProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'اليوم',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            daily.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, _) => const Text('تعذر تحميل مؤشرات اليوم.'),
              data: (d) => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
                children: [
                  _KpiTile(
                    label: 'مبيعات اليوم',
                    value: '${d.salesDay}',
                    color: Colors.green,
                    onTap: () => _open(
                      context,
                      ref,
                      const LocalSalesScreen(),
                      () => ref.invalidate(localSalesPageProvider),
                    ),
                  ),
                  _KpiTile(
                    label: 'مشتريات اليوم',
                    value: '${d.purchasesDay}',
                    color: Colors.blue,
                    onTap: () => _open(
                      context,
                      ref,
                      const LocalPurchasesScreen(),
                      () => ref.invalidate(localPurchasesPageProvider),
                    ),
                  ),
                  _KpiTile(
                    label: 'ربح اليوم',
                    value: '${d.profitDay}',
                    color: d.profitDay >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'الإجماليات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            totals.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (t) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.4,
                children: [
                  _KpiTile(
                    label: 'صافي المبيعات',
                    value: '${t.salesTotal}',
                    color: Colors.green,
                    onTap: () => _open(
                      context,
                      ref,
                      const LocalSalesScreen(),
                      () => ref.invalidate(localSalesPageProvider),
                    ),
                  ),
                  _KpiTile(
                    label: 'صافي المشتريات',
                    value: '${t.purchasesTotal}',
                    color: Colors.blue,
                    onTap: () => _open(
                      context,
                      ref,
                      const LocalPurchasesScreen(),
                      () => ref.invalidate(localPurchasesPageProvider),
                    ),
                  ),
                  _KpiTile(
                    label: 'قيمة المخزون',
                    value: '${t.inventoryValue}',
                    color: Colors.indigo,
                    onTap: () => _open(
                      context,
                      ref,
                      const LocalWarehousesScreen(),
                      () => ref.invalidate(localWarehousesProvider),
                    ),
                  ),
                  _KpiTile(
                    label: 'مستحقات العملاء',
                    value: '${t.customerOutstanding}',
                    color: Colors.orange,
                  ),
                  _KpiTile(
                    label: 'مستحقات الموردين',
                    value: '${t.supplierOutstanding}',
                    color: Colors.purple,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'الوحدات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _ModuleTile(
              icon: Icons.receipt_long_outlined,
              title: 'المبيعات',
              onTap: () => _open(
                context,
                ref,
                const LocalSalesScreen(),
                () => ref.invalidate(localSalesPageProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.shopping_cart_outlined,
              title: 'المشتريات',
              onTap: () => _open(
                context,
                ref,
                const LocalPurchasesScreen(),
                () => ref.invalidate(localPurchasesPageProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.inventory_2_outlined,
              title: 'الأصناف',
              onTap: () => _open(
                context,
                ref,
                const LocalProductsListScreen(),
                () => ref.invalidate(localProductsPageProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.warehouse_outlined,
              title: 'المخازن والمخزون',
              onTap: () => _open(
                context,
                ref,
                const LocalWarehousesScreen(),
                () => ref.invalidate(localWarehousesProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.person_outlined,
              title: 'العملاء',
              onTap: () => _open(
                context,
                ref,
                const LocalPartnersScreen(supplier: false),
                () => ref.invalidate(localCustomersPageProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.handshake_outlined,
              title: 'الموردون',
              onTap: () => _open(
                context,
                ref,
                const LocalPartnersScreen(supplier: true),
                () => ref.invalidate(localSuppliersPageProvider),
              ),
            ),
            _ModuleTile(
              icon: Icons.payments_outlined,
              title: 'المدفوعات',
              onTap: () => _open(
                context,
                ref,
                const LocalPaymentsScreen(),
                () => ref.invalidate(localPaymentsPageProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// فتح شاشة ثم تحديث بياناتها ومؤشرات الرئيسية
  /// عند الرجوع (إبطال الفاميلي بدون وسائط = كل نسخه).
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Widget page,
    void Function() refresh,
  ) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    refresh();
    ref.invalidate(localTotalsProvider);
    ref.invalidate(localDailyProvider);
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _KpiTile({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  const _ModuleTile({required this.icon, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        trailing: onTap == null
            ? const Text(
                'قريبا',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            : const Icon(Icons.chevron_left_outlined),
        onTap: onTap,
      ),
    );
  }
}
