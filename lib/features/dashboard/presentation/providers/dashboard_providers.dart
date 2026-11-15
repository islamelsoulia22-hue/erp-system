import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../expenses/data/expenses_repository.dart';
import '../../../manufacturing/data/manufacturing_repository.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../reports/data/reports_repository.dart';
import '../../../sales/data/sales_repository.dart';

/// Unified approval document across modules.
class ApprovalDoc {
  final String id;
  final String number;
  final String type;
  final String typeAr;
  final String? partner;
  final double amount;
  final DateTime date;
  final String route;
  const ApprovalDoc({
    required this.id,
    required this.number,
    required this.type,
    required this.typeAr,
    this.partner,
    required this.amount,
    required this.date,
    required this.route,
  });
}

final dashboardKpisProvider =
    FutureProvider.autoDispose<ErpKpis>((ref) {
  return ref.watch(reportsRepositoryProvider).dashboardKpis();
});

/// مؤشرات اليوم (مبيعات/مشتريات/ربح اليوم) للداشبورد.
final dashboardDailyProvider =
    FutureProvider.autoDispose<DailyKpis>((ref) {
  return ref
      .watch(reportsRepositoryProvider)
      .dailyKpis();
});

final recentActivityProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref
      .watch(reportsRepositoryProvider)
      .recentActivity();
});

/// Pending approvals visible to the current user, newest first.
/// Each source degrades to empty when the role lacks access.
/// نسخة الجهاز: بدون مركز موافقات نهائيا (حفظ مباشر) — ترجع فارغة.
final pendingApprovalsProvider =
    FutureProvider.autoDispose<List<ApprovalDoc>>((ref) async {
  final local = resolveBackendMode() == BackendMode.local;
  if (local) return <ApprovalDoc>[];
  final perms = await ref.watch(myPermissionsProvider.future);
  final docs = <ApprovalDoc>[];

  Future<void> guard(
      bool allowed, Future<void> Function() fn) async {
    if (!allowed) return;
    try {
      await fn();
    } catch (_) {}
  }

  await guard(
      perms.can(Permissions.salesView) ||
          perms.can(Permissions.salesApprove), () async {
    final rows = await ref
        .read(salesRepositoryProvider)
        .list(status: 'PENDING_APPROVAL', pageSize: 20);
    docs.addAll(rows.map((e) => ApprovalDoc(
          id: e.id,
          number: e.number,
          type: 'sales',
          typeAr: 'مبيعات',
          partner: e.customerName,
          amount: e.grandTotal,
          date: e.createdAt,
          route: '/sales/${e.id}',
        )));
  });

  await guard(
      perms.can(Permissions.purchasesView) ||
          perms.can(Permissions.purchasesApprove), () async {
    final rows = await ref
        .read(purchasesRepositoryProvider)
        .listInvoices(status: 'PENDING_APPROVAL');
    docs.addAll(rows.map((e) => ApprovalDoc(
          id: e.id,
          number: e.number,
          type: 'purchases',
          typeAr: 'مشتريات',
          partner: e.supplierName,
          amount: e.grandTotal,
          date: e.createdAt,
          route: '/purchase-invoices/${e.id}',
        )));
  });

  await guard(!local && perms.can(Permissions.purchasesView), () async {
    final rows = await ref
        .read(procurementRepositoryProvider)
        .list(status: 'PENDING_APPROVAL');
    docs.addAll(rows.map((e) => ApprovalDoc(
          id: e.id,
          number: e.number,
          type: 'procurement',
          typeAr: 'توريد',
          partner: e.supplierName,
          amount: 0,
          date: e.createdAt,
          route: '/procurement/${e.id}',
        )));
  });

  await guard(!local && perms.can(Permissions.salesView), () async {
    final rows = await ref
        .read(manufacturingRepositoryProvider)
        .listCustomized(status: 'PENDING_APPROVAL');
    docs.addAll(rows.map((e) => ApprovalDoc(
          id: e.id,
          number: e.code,
          type: 'customized',
          typeAr: 'صنف مخصص',
          partner: e.name,
          amount: e.totalPrice,
          date: e.createdAt,
          route: '/customized/${e.id}',
        )));
  });

  await guard(
      !local &&
          (perms.can(Permissions.expensesView) ||
              perms.can(Permissions.expensesApprove)), () async {
    final rows = await ref
        .read(expensesRepositoryProvider)
        .list(status: 'PENDING_APPROVAL', pageSize: 20);
    docs.addAll(rows.map((e) => ApprovalDoc(
          id: e.id,
          number: e.number,
          type: 'expenses',
          typeAr: 'مصروفات',
          partner: e.categoryName ?? e.partyName,
          amount: e.amount,
          date: e.createdAt,
          route: '/expenses/${e.id}',
        )));
  });

  docs.sort((a, b) => b.date.compareTo(a.date));
  return docs;
});
