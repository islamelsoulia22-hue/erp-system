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
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../expenses/data/expenses_repository.dart';
import '../../../manufacturing/data/customized_from_invoice.dart';
import '../../../manufacturing/data/manufacturing_repository.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../sales/data/sales_repository.dart';
import '../widgets/approval_preview_dialog.dart';

/// صلاحية الاعتماد المطلوبة لكل نوع مستند (نفس شروط الـ RPC في السيرفر).
/// المدير (company_manager) معاه الكل؛ باقي الأدوار بتشوف "قيد المراجعة".
String approvalPermissionFor(String type) {
  switch (type) {
    case 'sales':
    case 'customized':
      return Permissions.salesApprove;
    case 'purchases':
    case 'procurement':
      return Permissions.purchasesApprove;
    case 'expenses':
      return Permissions.expensesApprove;
    default:
      return Permissions.usersManage;
  }
}

/// Dedicated approval center with type tabs.
/// Uses existing repositories and RPCs; UI only.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() =>
      _ApprovalsScreenState();
}

class _ApprovalsScreenState
    extends ConsumerState<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'الكل'),
              Tab(text: 'مبيعات'),
              Tab(text: 'مشتريات'),
              Tab(text: 'توريد'),
              Tab(text: 'مخصص'),
              Tab(text: 'مصروفات'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _ApprovalList(filter: null),
              _ApprovalList(filter: 'sales'),
              _ApprovalList(filter: 'purchases'),
              _ApprovalList(filter: 'procurement'),
              _ApprovalList(filter: 'customized'),
              _ApprovalList(filter: 'expenses'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ApprovalList extends ConsumerStatefulWidget {
  final String? filter;
  const _ApprovalList({this.filter});

  @override
  ConsumerState<_ApprovalList> createState() =>
      _ApprovalListState();
}

class _ApprovalListState
    extends ConsumerState<_ApprovalList> {
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingApprovalsProvider);
    final filter = widget.filter;
    return pending.when(
      loading: () => const LoadingSkeleton(rows: 5),
      error: (_, _) => const ErrorState(),
      data: (docs) {
        final rows = filter == null
            ? docs
            : docs.where((d) => d.type == filter).toList();
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'لا توجد موافقات معلقة',
          );
        }
        final items = paginateLocal(rows, _page);
        return Column(
          children: [
            Expanded(
              child: context.isMobile
                  ? ListView.separated(
                      padding: EdgeInsets.all(
                          context.contentPadding),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(
                              height: AppSpacing.sm),
                      itemBuilder: (context, i) =>
                          _ApprovalCard(
                              doc: items[i]),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(
                          context.contentPadding),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: context.columns(
                            mobile: 1,
                            tablet: 2,
                            desktop: 3),
                        mainAxisSpacing:
                            AppSpacing.sm,
                        crossAxisSpacing:
                            AppSpacing.sm,
                        mainAxisExtent: 252,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) =>
                          _ApprovalCard(
                              doc: items[i]),
                    ),
            ),
            AppPagination(
              page: _page,
              total: rows.length,
              onGo: _go,
            ),
          ],
        );
      },
    );
  }
}

class _ApprovalCard extends ConsumerStatefulWidget {
  final ApprovalDoc doc;
  const _ApprovalCard({required this.doc});

  @override
  ConsumerState<_ApprovalCard> createState() =>
      _ApprovalCardState();
}

class _ApprovalCardState
    extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    String? extraMsg;
    try {
      final ref = this.ref;
      switch (widget.doc.type) {
        case 'sales':
          await ref
              .read(salesRepositoryProvider)
              .approve(widget.doc.id);
        case 'purchases':
          await ref
              .read(purchasesRepositoryProvider)
              .approveInvoice(widget.doc.id);
        case 'procurement':
          await ref
              .read(procurementRepositoryProvider)
              .approve(widget.doc.id);
        case 'customized':
          // اعتماد طلب التصنيع + إنشاء أمر التصنيع تلقائيا.
          extraMsg = await approveCustomizedAndMakeOrder(
              ref, widget.doc.id);
        case 'expenses':
          await ref
              .read(expensesRepositoryProvider)
              .approve(widget.doc.id);
      }
      ref.invalidate(pendingApprovalsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                extraMsg ?? 'تم الاعتماد بنجاح.')));
      }
    } catch (e) {
      debugPrint(
          'approvals.approve RAW error: $e (${e.runtimeType}) type=${widget.doc.type} id=${widget.doc.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is AppFailure
                  ? e.messageAr
                  : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سبب الرفض'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'السبب *'),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(ctx)
                .pop(ctrl.text.trim()),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final ref = this.ref;
      switch (widget.doc.type) {
        case 'sales':
          await ref
              .read(salesRepositoryProvider)
              .reject(widget.doc.id, reason);
        case 'purchases':
          await ref
              .read(purchasesRepositoryProvider)
              .rejectInvoice(widget.doc.id, reason);
        case 'procurement':
          await ref
              .read(procurementRepositoryProvider)
              .reject(widget.doc.id, reason);
        case 'customized':
          await ref
              .read(manufacturingRepositoryProvider)
              .rejectCustomized(widget.doc.id, reason);
        case 'expenses':
          await ref
              .read(expensesRepositoryProvider)
              .reject(widget.doc.id, reason);
      }
      ref.invalidate(pendingApprovalsProvider);
    } catch (e) {
      debugPrint(
          'approvals.reject RAW error: $e (${e.runtimeType}) type=${widget.doc.type} id=${widget.doc.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is AppFailure
                  ? e.messageAr
                  : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.doc;
    // الاعتماد للمدير فقط (معاه صلاحية النوع)؛ غيره يشوف "قيد المراجعة".
    final canAct = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(approvalPermissionFor(d.type)),
          orElse: () => false,
        );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d.number,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleMedium),
              ),
              AppStatus.badge('PENDING_APPROVAL'),
            ],
          ),
          Text('${d.typeAr} • ${d.partner ?? ''}',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(
              '${AppFormat.money(d.amount)} • ${AppFormat.date(d.date)}',
              style: theme.textTheme.bodySmall),
          // مسافة ثابتة بدل Spacer: الكارت جوه ListView/GridView
          // بارتفاع غير محدود، والـ Spacer (flex) بيضرب layout.
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => context.push(d.route),
                  child: const Text('فتح'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => showApprovalPreview(context, d),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('معاينة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (canAct)
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _reject,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _approve,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child:
                                CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                        : const Text('اعتماد'),
                  ),
                ),
              ],
            )
          else
            const Text(
              'قيد المراجعة — الاعتماد للمدير فقط.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
