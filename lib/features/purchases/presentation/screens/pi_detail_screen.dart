import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/attachments/widgets/attachments_section.dart';
import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/invoice_pdf.dart';
import '../../../../core/printing/usb_receipt_printer.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../returns/presentation/widgets/invoice_returns_card.dart';
import '../../data/purchases_repository.dart';
import '../../domain/purchases.dart';
import '../providers/purchases_providers.dart';

class PurchaseInvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const PurchaseInvoiceDetailScreen(
      {super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(piDetailProvider(invoiceId));
    final items = ref.watch(piItemsProvider(invoiceId));
    final myId =
        ref.watch(authRepositoryProvider).currentUser?.id;
    final canApprove = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.purchasesApprove),
          orElse: () => false,
        );
    final isCompanyManager =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) => p.isCompanyManager,
              orElse: () => false,
            );

    return Scaffold(
            body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('حدث خطأ: $e')),
        data: (v) {
          if (v == null) {
            return const Center(child: Text('الفاتورة غير موجودة.'));
          }
          final isMine = v.createdBy != null && v.createdBy == myId;
          final draft = v.status == 'DRAFT' || v.status == 'REJECTED';
          final pending = v.status == 'PENDING_APPROVAL';
          // نسخة الجهاز: بدون مركز موافقات — اعتماد ونزول مخزون مباشر.
          final isLocal =
              resolveBackendMode() == BackendMode.local;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(v.number,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                  '${v.supplierName ?? 'مورد'} • ${AppStatus.labelOf(v.status)}'),
              if (v.rejectionReason != null)
                Card(
                    color: Colors.red.shade50,
                    child: ListTile(
                        title: Text(
                            'سبب الرفض: ${v.rejectionReason}'))),
              const Divider(height: 24),
              items.when(
                loading: () => const Center(
                    child: CircularProgressIndicator()),
                error: (e, _) => Text('تعذر التحميل: $e'),
                data: (rows) => Column(
                  children: [
                    for (final it in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(it.productName),
                        subtitle: Text(
                            '${it.quantity} × ${it.unitCost} = ${it.total.toStringAsFixed(2)}'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Text(
                  'الإجمالي: ${v.grandTotal.toStringAsFixed(2)} ج.م',
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'طريقة الدفع: ${v.paymentMethodName ?? '—'}',
                  style: const TextStyle(color: Colors.grey)),
              Text(
                v.paymentStatus == 'PAID'
                    ? 'حالة السداد: مدفوعة بالكامل'
                    : v.paymentStatus == 'PARTIAL'
                        ? 'حالة السداد: مدفوعة جزئيا'
                        : 'حالة السداد: غير مدفوعة (آجل)',
                style: const TextStyle(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Builder(builder: (_) {
                // غير الآجل = اتدفعت للمورد خلاص ومش بتنزل مستحقات.
                // الآجل (أو بدون طريقة) = الباقي بعد المدفوع بينزل
                // في مستحقات المورد، وممكن متدفعش خالص عادي.
                final isCredit =
                    v.paymentMethodCode == null ||
                        v.paymentMethodCode == 'CREDIT';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCredit
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCredit
                        ? 'آجل: المتبقي بعد المدفوع هينزل في مستحقات المورد. ممكن متدفعش حاجة خالص عادي.'
                        : 'مدفوعة (${v.paymentMethodName ?? '—'}): مش هتنزل في المستحقات بعد الاعتماد.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isCredit
                          ? Colors.orange.shade900
                          : Colors.green.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }),
              const Text(
                  'اعتماد الفاتورة ينزل الكمية في مخزن الفاتورة (لو بدون طلب مرتبط — المرتبطة بطلب مخزونها دخل بالاستلام).',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              // الخياران جنب بعض: طباعة PDF (كل المنصات) + ريسيت (لينكس).
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        _printPdf(context, ref, v),
                    icon: const Icon(
                        Icons.print_outlined,
                        size: 18),
                    label: const Text('طباعة PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _share(context, ref, v),
                    icon: const Icon(
                        Icons.share_outlined,
                        size: 18),
                    label: const Text('مشاركة PDF'),
                  ),
                  if (supportsUsbReceiptPrint)
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _printReceipt(context, ref, v),
                      icon: const Icon(
                          Icons.receipt_long_outlined,
                          size: 18),
                      label:
                          const Text('طباعة ريسيت'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // نسخة الجهاز: اعتماد ونزول مخزون مباشر.
              if (isLocal && (draft || pending))
                FilledButton.icon(
                  onPressed: () =>
                      _approveDirectLocal(context, ref, v.id, draft),
                  icon: const Icon(
                      Icons.check_circle_outline,
                      size: 18),
                  label: const Text(
                      'حفظ واعتماد (نزول المخزون فوري)'),
                ),
              if (!isLocal && draft)
                FilledButton(
                  onPressed: () => _act(
                      context,
                      ref,
                      () => ref
                          .read(purchasesRepositoryProvider)
                          .submitInvoice(v.id)),
                  child: const Text('إرسال للاعتماد'),
                ),
              if (!isLocal &&
                  pending &&
                  canApprove &&
                  (!isMine || isCompanyManager)) ...[
                FilledButton(
                  onPressed: () => _act(
                      context,
                      ref,
                      () => ref
                          .read(purchasesRepositoryProvider)
                          .approveInvoice(v.id)),
                  child: const Text('اعتماد'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      _rejectSheet(context, ref, v.id),
                  child: const Text('رفض بسبب'),
                ),
              ],
              if (!isLocal &&
                  pending &&
                  isMine &&
                  !isCompanyManager)
                const Text(
                    'فاتورتك بانتظار الاعتماد — لا يمكنك اعتمادها بنفسك.',
                    textAlign: TextAlign.center),
              if (!isLocal && pending && !canApprove)
                const Text(
                    'الفاتورة قيد المراجعة — الاعتماد للمدير فقط.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              if (v.status == 'APPROVED') ...[
                // المدفوعة بالكامل (غير الآجل بيتسدد تلقائيا
                // عند الاعتماد) لا تقبل دفعات زيادة.
                if (v.paymentStatus != 'PAID')
                  OutlinedButton(
                    onPressed: () => context.push(
                        '/payments/new?purchase=${v.id}'),
                    child:
                        const Text('تسجيل دفعة مورد'),
                  ),
                if (v.paymentStatus == 'PAID')
                  const Text(
                    'مدفوعة بالكامل — لا مستحقات عليها.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 12),
                  ),
                OutlinedButton(
                  onPressed: () => context.push(
                      '/purchase-returns/new?invoice=${v.id}'),
                  child: const Text('مرتجع مشتريات'),
                ),
              ],
              AttachmentsSection(
                  entityType: 'PURCHASE_INVOICE',
                  entityId: v.id),
              const SizedBox(height: 12),
              PurchaseInvoiceReturnsCard(invoiceId: v.id),
            ],
          );
        },
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(piDetailProvider(invoiceId))
        ..invalidate(piItemsProvider(invoiceId))
        ..invalidate(piPageProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  /// اعتماد مباشر (نسخة الجهاز فقط): إرسال (لو مسودة)
  /// + اعتماد + نزول المخزون فورا بدون موافقات.
  Future<void> _approveDirectLocal(BuildContext context,
      WidgetRef ref, String id, bool isDraft) async {
    final repo = ref.read(purchasesRepositoryProvider);
    try {
      if (isDraft) {
        await repo.submitInvoice(id);
      }
      await repo.approveInvoice(id);
      ref
        ..invalidate(piDetailProvider(invoiceId))
        ..invalidate(piItemsProvider(invoiceId))
        ..invalidate(piPageProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'تم الاعتماد ونزول الكمية في المخزن.')));
        context.pop();
      }
    } catch (e) {
      ref
        ..invalidate(piDetailProvider(invoiceId))
        ..invalidate(piItemsProvider(invoiceId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  /// بيانات PDF فاتورة المشتريات — مشتركة بين المشاركة والطباعة
  /// عشان الزرارين يطلعوا نفس الشكل بالظبط.
  InvoicePdfData _purchasePdfData(
      PurchaseInvoice v, List<PurchaseInvoiceItem> rows) {
    return InvoicePdfData(
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
      notes: v.rejectionReason != null
          ? 'سبب الرفض: ${v.rejectionReason}'
          : null,
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref,
      PurchaseInvoice v) async {
    try {
      final rows =
          await ref.read(piItemsProvider(v.id).future);
      if (!context.mounted) return;
      await shareInvoicePdf(
        context,
        _purchasePdfData(v, rows),
      );
    } catch (e, st) {
      debugPrint('share purchase pdf error: $e (${e.runtimeType})\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تعذر تجهيز ملف الـ PDF.')));
      }
    }
  }

  /// طباعة PDF عبر حوار الطباعة — شغالة على كل المنصات
  /// (موبايل/لينكس/ويندوز).
  Future<void> _printPdf(BuildContext context, WidgetRef ref,
      PurchaseInvoice v) async {
    try {
      final rows =
          await ref.read(piItemsProvider(v.id).future);
      if (!context.mounted) return;
      await printInvoicePdf(
        context,
        _purchasePdfData(v, rows),
      );
    } catch (e, st) {
      debugPrint('print purchase pdf error: $e (${e.runtimeType})\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تعذر تجهيز الطباعة.')));
      }
    }
  }

  /// طباعة فاتورة المشتريات على طابعة الريسيت الحراري USB (لينكس).
  Future<void> _printReceipt(BuildContext context, WidgetRef ref,
      PurchaseInvoice v) async {
    try {
      final rows =
          await ref.read(piItemsProvider(v.id).future);
      if (!context.mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('لا توجد أصناف في الفاتورة للطباعة.')),
        );
        return;
      }
      await printInvoiceUsbReceipt(
        context,
        ReceiptInvoiceData(
          title: 'فاتورة مشتريات',
          number: v.number,
          date: v.createdAt,
          partnerLabel: 'المورد',
          partnerName: v.supplierName ?? 'مورد',
          paymentLabel: v.paymentMethodName,
          rows: [
            for (final it in rows)
              ReceiptInvoiceRow(
                name: it.productName,
                qty: it.quantity,
                price: it.unitCost,
                total: it.total,
                discount: it.discount,
                taxRate: it.taxRate,
              ),
          ],
          subtotal: v.subtotal,
          discount: v.discount,
          taxAmount: v.taxAmount,
          total: v.grandTotal,
          notes: null,
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اتطبعت على الريسيت.')),
        );
      }
    } on UsbPrinterException catch (e) {
      if (context.mounted) await showUsbPrinterError(context, e);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الطباعة: $e')),
        );
      }
    }
  }

  void _rejectSheet(
      BuildContext context, WidgetRef ref, String id) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('سبب الرفض *',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
                controller: ctrl,
                decoration:
                    const InputDecoration(labelText: 'السبب')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop();
                await _act(
                    context,
                    ref,
                    () => ref
                        .read(purchasesRepositoryProvider)
                        .rejectInvoice(id, ctrl.text.trim()));
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
  }
}
