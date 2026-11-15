import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/invoice_pdf.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../expenses/data/expenses_repository.dart';
import '../../../expenses/presentation/providers/expenses_providers.dart';
import '../../../manufacturing/data/customized_from_invoice.dart';
import '../../../manufacturing/data/manufacturing_repository.dart';
import '../../../manufacturing/presentation/providers/manufacturing_providers.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../purchases/data/purchases_repository.dart';
import '../../../purchases/presentation/providers/purchases_providers.dart';
import '../../../sales/data/sales_repository.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../screens/approvals_screen.dart' show approvalPermissionFor;
import '../../../auth/presentation/providers/auth_providers.dart';

/// يفتح معاينة كاملة لشكل الفاتورة / المستند قبل الاعتماد.
Future<void> showApprovalPreview(
    BuildContext context, ApprovalDoc doc) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: _ApprovalPreviewBody(doc: doc),
      ),
    ),
  );
}

class _ApprovalPreviewBody extends ConsumerStatefulWidget {
  final ApprovalDoc doc;
  const _ApprovalPreviewBody({required this.doc});

  @override
  ConsumerState<_ApprovalPreviewBody> createState() =>
      _ApprovalPreviewBodyState();
}

class _ApprovalPreviewBodyState
    extends ConsumerState<_ApprovalPreviewBody> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    String? extraMsg;
    try {
      final d = widget.doc;
      switch (d.type) {
        case 'sales':
          await ref.read(salesRepositoryProvider).approve(d.id);
        case 'purchases':
          await ref
              .read(purchasesRepositoryProvider)
              .approveInvoice(d.id);
        case 'procurement':
          await ref.read(procurementRepositoryProvider).approve(d.id);
        case 'customized':
          extraMsg =
              await approveCustomizedAndMakeOrder(ref, d.id);
        case 'expenses':
          await ref
              .read(expensesRepositoryProvider)
              .approve(d.id);
      }
      ref.invalidate(pendingApprovalsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(extraMsg ?? 'تم الاعتماد بنجاح.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
          decoration:
              const InputDecoration(labelText: 'السبب *'),
          maxLines: 2,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final d = widget.doc;
      switch (d.type) {
        case 'sales':
          await ref.read(salesRepositoryProvider).reject(d.id, reason);
        case 'purchases':
          await ref
              .read(purchasesRepositoryProvider)
              .rejectInvoice(d.id, reason);
        case 'procurement':
          await ref
              .read(procurementRepositoryProvider)
              .reject(d.id, reason);
        case 'customized':
          await ref
              .read(manufacturingRepositoryProvider)
              .rejectCustomized(d.id, reason);
        case 'expenses':
          await ref
              .read(expensesRepositoryProvider)
              .reject(d.id, reason);
      }
      ref.invalidate(pendingApprovalsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc;
    final canAct = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(approvalPermissionFor(d.type)),
          orElse: () => false,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // هيدر المعاينة
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'معاينة ${d.typeAr} • ${d.number}',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildPreview(context, d),
          ),
        ),
        const Divider(height: 1),
        // أكشنز سريعة جوه المعاينة
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(d.route);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('فتح التفاصيل'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (canAct) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _approve,
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('اعتماد'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, ApprovalDoc d) {
    switch (d.type) {
      case 'sales':
        return _SalesPreview(invoiceId: d.id);
      case 'purchases':
        return _PurchasesPreview(invoiceId: d.id);
      case 'procurement':
        return _ProcurementPreview(requestId: d.id);
      case 'customized':
        return _CustomizedPreview(itemId: d.id);
      case 'expenses':
        return _ExpensePreview(expenseId: d.id);
      default:
        return const Text('نوع غير مدعوم.');
    }
  }
}

// ---------- مبيعات ----------
class _SalesPreview extends ConsumerWidget {
  final String invoiceId;
  const _SalesPreview({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(salesDetailProvider(invoiceId));
    final items = ref.watch(salesItemsProvider(invoiceId));
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 5),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل الفاتورة.'),
      data: (inv) {
        if (inv == null) return const Text('الفاتورة غير موجودة.');
        return items.when(
          loading: () => const LoadingSkeleton(rows: 4),
          error: (_, _) =>
              const ErrorState(message: 'تعذر تحميل الأصناف.'),
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShareRow(
                onShare: () => _shareSales(context, ref, inv.id),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: InvoicePreview(
                  data: InvoicePdfData(
                    title: 'فاتورة مبيعات',
                    number: inv.number,
                    date: inv.createdAt,
                    partnerLabel: 'العميل',
                    partnerName:
                        inv.customerName ?? 'عميل نقدي',
                    warehouseName: inv.warehouseName,
                    paymentLabel: inv.paymentMethodName,
                    referenceNumber: inv.reference,
                    statusAr: AppStatus.labelOf(inv.status),
                    rows: [
                      for (final it in rows)
                        InvoicePdfRow(
                          name:
                              '${it.isCustom ? '🔧 ' : ''}${it.itemName}${it.isCustom && it.specSummary.isNotEmpty ? ' (${it.specSummary})' : ''}',
                          qty: it.quantity,
                          price: it.unitPrice,
                          discount: it.discount,
                          taxRate: it.taxRate,
                          total: it.total,
                        ),
                    ],
                    subtotal: inv.subtotal,
                    discount: inv.discount,
                    taxAmount: inv.taxAmount,
                    total: inv.grandTotal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareSales(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      final inv = await ref.read(salesDetailProvider(id).future);
      final rows = await ref.read(salesItemsProvider(id).future);
      if (inv == null || !context.mounted) return;
      await shareInvoicePdf(
        context,
        InvoicePdfData(
          title: 'فاتورة مبيعات',
          number: inv.number,
          date: inv.createdAt,
          partnerLabel: 'العميل',
          partnerName: inv.customerName ?? 'عميل نقدي',
          warehouseName: inv.warehouseName,
          paymentLabel: inv.paymentMethodName,
          referenceNumber: inv.reference,
          statusAr: AppStatus.labelOf(inv.status),
          rows: [
            for (final it in rows)
              InvoicePdfRow(
                name:
                    '${it.isCustom ? '🔧 ' : ''}${it.itemName}${it.isCustom && it.specSummary.isNotEmpty ? ' (${it.specSummary})' : ''}',
                qty: it.quantity,
                price: it.unitPrice,
                discount: it.discount,
                taxRate: it.taxRate,
                total: it.total,
              ),
          ],
          subtotal: inv.subtotal,
          discount: inv.discount,
          taxAmount: inv.taxAmount,
          total: inv.grandTotal,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر تجهيز ملف الـ PDF.')));
      }
    }
  }
}

// ---------- مشتريات ----------
class _PurchasesPreview extends ConsumerWidget {
  final String invoiceId;
  const _PurchasesPreview({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(piDetailProvider(invoiceId));
    final items = ref.watch(piItemsProvider(invoiceId));
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 5),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل الفاتورة.'),
      data: (v) {
        if (v == null) return const Text('الفاتورة غير موجودة.');
        return items.when(
          loading: () => const LoadingSkeleton(rows: 4),
          error: (_, _) =>
              const ErrorState(message: 'تعذر تحميل الأصناف.'),
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ShareRow(
                onShare: () => _share(context, ref, v.id),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: InvoicePreview(
                  data: InvoicePdfData(
                    title: 'فاتورة مشتريات',
                    number: v.number,
                    date: v.createdAt,
                    partnerLabel: 'المورد',
                    partnerName: v.supplierName ?? 'مورد',
                    warehouseName: v.warehouseName,
                    paymentLabel: v.paymentMethodName,
                    referenceNumber: v.referenceNumber,
                    statusAr: AppStatus.labelOf(v.status),
                    rows: [
                      for (final it in rows)
                        InvoicePdfRow(
                          name: it.productName,
                          qty: it.quantity,
                          price: it.unitCost,
                          discount: it.discount,
                          taxRate: it.taxRate,
                          total: it.total,
                        ),
                    ],
                    subtotal: v.subtotal,
                    discount: v.discount,
                    taxAmount: v.taxAmount,
                    total: v.grandTotal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _share(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      final v = await ref.read(piDetailProvider(id).future);
      final rows = await ref.read(piItemsProvider(id).future);
      if (v == null || !context.mounted) return;
      await shareInvoicePdf(
        context,
        InvoicePdfData(
          title: 'فاتورة مشتريات',
          number: v.number,
          date: v.createdAt,
          partnerLabel: 'المورد',
          partnerName: v.supplierName ?? 'مورد',
          warehouseName: v.warehouseName,
          paymentLabel: v.paymentMethodName,
          referenceNumber: v.referenceNumber,
          statusAr: AppStatus.labelOf(v.status),
          rows: [
            for (final it in rows)
              InvoicePdfRow(
                name: it.productName,
                qty: it.quantity,
                price: it.unitCost,
                discount: it.discount,
                taxRate: it.taxRate,
                total: it.total,
              ),
          ],
          subtotal: v.subtotal,
          discount: v.discount,
          taxAmount: v.taxAmount,
          total: v.grandTotal,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر تجهيز ملف الـ PDF.')));
      }
    }
  }
}

// ---------- توريد ----------
class _ProcurementPreview extends ConsumerWidget {
  final String requestId;
  const _ProcurementPreview({required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(procurementDetailProvider(requestId));
    final items = ref.watch(procurementItemsProvider(requestId));
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 4),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل الطلب.'),
      data: (r) {
        if (r == null) return const Text('الطلب غير موجود.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.number,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.titleLarge),
            Text(
                '${r.supplierName ?? 'بدون مورد'} • ${AppStatus.labelOf(r.status)}'),
            if (r.reason != null) Text('السبب: ${r.reason}'),
            // مربوط بفاتورة مبيعات (حجز): اعرض رقمها وعميلها.
            if (r.salesInvoiceId != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'مرتبط بفاتورة مبيعات ${r.salesInvoiceNumber?.isNotEmpty == true ? r.salesInvoiceNumber : ''} — ${r.salesCustomerName ?? ''} (إجمالي ${r.salesGrandTotal}) — التفاصيل والحجز في صفحة الطلب.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
            const Divider(height: 20),
            const Text('الأصناف (مطلوب / متاح / ناقص / مستلم)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            items.when(
              loading: () => const LoadingSkeleton(rows: 3),
              error: (_, _) => const Text('تعذر تحميل الأصناف.'),
              data: (rows) => Column(
                children: [
                  for (final it in rows)
                    Card(
                      margin:
                          const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(it.productName ?? 'صنف'),
                        subtitle: Text(
                            'مطلوب ${it.requested} • متاح ${it.available} • ناقص ${it.missing} • مستلم ${it.received}'),
                      ),
                    ),
                  if (rows.isEmpty)
                    const Text('لا توجد أصناف.'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------- صنف مخصص ----------
class _CustomizedPreview extends ConsumerWidget {
  final String itemId;
  const _CustomizedPreview({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(czDetailProvider(itemId));
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 4),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل الصنف.'),
      data: (c) {
        if (c == null) return const Text('الصنف غير موجود.');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🔧 ${c.name}',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(c.code,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                  '${AppStatus.labelOf(c.status)} • ${c.quantity} × ${c.unitPrice} = ${c.totalPrice.toStringAsFixed(2)}'),
              if (c.specSummary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('المقاس والخامة: ${c.specSummary}',
                    style:
                        Theme.of(context).textTheme.bodyMedium),
              ],
              if (c.unit != null)
                Text('الوحدة: ${c.unit!}'),
              if (c.createdByName != null)
                Text('أنشأ الطلب: ${c.createdByName!}'),
              if (c.salesInvoiceId != null) ...[
                const SizedBox(height: 8),
                _PreviewInvoiceLine(
                    invoiceId: c.salesInvoiceId!),
              ],
              if (c.description != null) ...[
                const SizedBox(height: 8),
                Text(c.description!),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// سطر الفاتورة المصدر داخل معاينة طلب التصنيع.
class _PreviewInvoiceLine extends ConsumerWidget {
  final String invoiceId;
  const _PreviewInvoiceLine({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(salesDetailProvider(invoiceId));
    return inv.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) {
        if (v == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'ناتج عن فاتورة: ${v.number} • ${v.customerName ?? 'عميل نقدي'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}

class _ExpensePreview extends ConsumerWidget {
  final String expenseId;
  const _ExpensePreview({required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(expenseDetailProvider(expenseId));
    return detail.when(
      loading: () => const LoadingSkeleton(rows: 4),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل المصروف.'),
      data: (e) {
        if (e == null) return const Text('المصروف غير موجود.');
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title,
                  style: Theme.of(context).textTheme.titleLarge),
              Text(e.number,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                  '${e.categoryName ?? 'بدون تصنيف'} • ${e.amount.toStringAsFixed(2)} ج.م'),
              if (e.partyName != null)
                Text('الجهة: ${e.partyName!}'),
              if (e.paymentMethodName != null)
                Text('الدفع: ${e.paymentMethodName!}'),
              if (e.notes != null) ...[
                const SizedBox(height: 8),
                Text(e.notes!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ShareRow extends StatelessWidget {  final VoidCallback onShare;
  const _ShareRow({required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        onPressed: onShare,
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('مشاركة PDF'),
      ),
    );
  }
}
