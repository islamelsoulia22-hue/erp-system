import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/attachments/widgets/attachments_section.dart';
import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/invoice_pdf.dart';
import '../../../../core/printing/usb_receipt_printer.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../manufacturing/data/customized_from_invoice.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../procurement/domain/procurement.dart';
import '../../../products/data/products_repository.dart';
import '../../../returns/presentation/widgets/invoice_returns_card.dart';
import '../../../serials/presentation/widgets/register_serial_sheet.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../data/sales_repository.dart';
import '../../domain/sales.dart';
import '../providers/sales_providers.dart';
import '../widgets/reservation_flow.dart';

/// Professional invoice page: header + customer + items table +
/// financial summary + approval timeline + actions + attachments.
class SalesDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const SalesDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(salesDetailProvider(invoiceId));
    final items = ref.watch(salesItemsProvider(invoiceId));
    final myId =
        ref.watch(authRepositoryProvider).currentUser?.id;
    final canApprove = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.salesApprove),
          orElse: () => false,
        );
    // مدير الشركة معفي من منع الاعتماد الذاتي (نفس قاعدة السيرفر).
    final isCompanyManager =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) => p.isCompanyManager,
              orElse: () => false,
            );
    final canRegisterSerial =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) =>
                  p.can(Permissions.salesCreate) ||
                  p.can(Permissions.salesEdit),
              orElse: () => false,
            );

    return detail.when(
      loading: () => const LoadingSkeleton(rows: 6),
      error: (_, _) => const ErrorState(),
      data: (inv) {
        if (inv == null) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'الفاتورة غير موجودة.',
          );
        }
        final isMine =
            inv.createdBy != null && inv.createdBy == myId;
        final canSubmit =
            inv.status == 'DRAFT' || inv.status == 'REJECTED';
        final pending = inv.status == 'PENDING_APPROVAL';
        // نسخة الجهاز: بدون مركز موافقات — اعتماد وخصم مباشر.
        final isLocal =
            resolveBackendMode() == BackendMode.local;

        return ResponsiveLayout(
          mobile: ListView(
            padding:
                EdgeInsets.all(context.contentPadding),
            children: [
              _HeaderCard(
                  number: inv.number,
                  status: inv.status,
                  date: inv.createdAt,
                  reference: inv.reference),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                        title: 'العميل'),
                    _InfoRow(
                        label: 'الاسم',
                        value: inv.customerName ??
                            'عميل نقدي'),
                    if (inv.reference != null)
                      _InfoRow(
                          label: 'مرجع',
                          value: inv.reference!),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const SectionHeader(title: 'الأصناف'),
              if (canSubmit)
                _DraftItemsEditor(invoiceId: inv.id)
              else
                items.when(
                loading: () =>
                    const LoadingSkeleton(rows: 3),
                error: (_, _) => const ErrorState(
                    message: 'تعذر تحميل الأصناف.'),
                data: (rows) => ResponsiveTable<SalesInvoiceItem?>(
                  columns: [
                    TableColumn<SalesInvoiceItem?>(
                        label: 'الصنف',
                        value: (i) =>
                            '${i?.isCustom == true ? '🔧 ' : ''}${i?.itemName ?? ''}${i?.isCustom == true && i?.specSummary.isNotEmpty == true ? ' (${i!.specSummary})' : ''}${(i?.serialNumbers.isNotEmpty == true) ? ' • سيريال: ${i!.serialNumbers.join(', ')}' : ''}'),
                    TableColumn<SalesInvoiceItem?>(
                        label: 'الكمية',
                        numeric: true,
                        value: (i) =>
                            '${i?.quantity ?? 0}'),
                    TableColumn<SalesInvoiceItem?>(
                        label: 'السعر',
                        numeric: true,
                        value: (i) => AppFormat.money(
                            i?.unitPrice ?? 0,
                            suffix: '')),
                    TableColumn<SalesInvoiceItem?>(
                        label: 'الخصم',
                        numeric: true,
                        value: (i) => AppFormat.money(
                            i?.discount ?? 0,
                            suffix: '')),
                    TableColumn<SalesInvoiceItem?>(
                        label: 'الإجمالي',
                        numeric: true,
                        value: (i) => AppFormat.money(
                            i?.total ?? 0,
                            suffix: '')),
                  ],
                  rows: rows,
                  cardBuilder: (it) => AppCard(
                    padding: const EdgeInsets.all(
                        AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                  '${it?.isCustom == true ? '🔧 ' : ''}${it?.itemName ?? ''}',
                                  style:
                                      Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                              Text(
                                '${it?.quantity ?? 0} × ${AppFormat.money(it?.unitPrice ?? 0)}',
                                style: Theme.of(
                                        context)
                                    .textTheme
                                    .bodySmall,
                              ),
                              if (it?.isCustom == true &&
                                  (it?.specSummary
                                          .isNotEmpty ==
                                      true))
                                Text(
                                  it!.specSummary,
                                  style: Theme.of(
                                          context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Colors
                                              .grey),
                                ),
                              if (it?.serialNumbers
                                      .isNotEmpty ==
                                  true)
                                Text(
                                  'سيريال: ${it!.serialNumbers.join(', ')}',
                                  textDirection:
                                      TextDirection.ltr,
                                  style: Theme.of(
                                          context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Colors
                                              .blue
                                              .shade900),
                                ),
                            ],
                          ),
                        ),
                        Text(
                            AppFormat.money(
                                it?.total ?? 0),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                        title: 'الملخص المالي'),
                    _InfoRow(
                        label: 'الإجمالي الفرعي',
                        value: AppFormat.money(
                            inv.subtotal)),
                    _InfoRow(
                        label: 'الخصم',
                        value: AppFormat.money(
                            inv.discount)),
                    _InfoRow(
                        label: 'الضريبة',
                        value: AppFormat.money(
                            inv.taxAmount)),
                    const Divider(),
                    _InfoRow(
                      label: 'الإجمالي',
                      value: AppFormat.money(
                          inv.grandTotal),
                      bold: true,
                    ),
                    const Divider(),
                    _InfoRow(
                      label: 'طريقة الدفع',
                      value: inv.paymentMethodName ?? '—',
                    ),
                    _InfoRow(
                      label: 'حالة السداد',
                      value: inv.paymentStatus == 'PAID'
                          ? 'مدفوعة بالكامل'
                          : inv.paymentStatus == 'PARTIAL'
                              ? 'مدفوعة جزئيا (عربون)'
                              : 'غير مدفوعة (آجل)',
                      bold: true,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (inv.paymentMethodCode == 'CREDIT')
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (inv.paymentMethodCode == 'CREDIT')
                            ? 'آجل: المتبقي بعد العربون هينزل في مستحقات العميل. سجل العربون من (تسجيل دفعة).'
                            : 'مدفوعة (${inv.paymentMethodName ?? '—'}): مش هتنزل في المستحقات.',
                        style: TextStyle(
                          fontSize: 12,
                          color: (inv.paymentMethodCode == 'CREDIT')
                              ? Colors.orange.shade900
                              : Colors.green.shade900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _InvoiceProfitCard(invoiceId: inv.id),
              const SizedBox(height: AppSpacing.md),
              SalesInvoiceReturnsCard(invoiceId: inv.id),
              if (inv.rejectionReason != null) ...[
                const SizedBox(
                    height: AppSpacing.md),
                AppCard(
                  child: Row(
                    children: [
                      const Icon(
                          Icons.info_outline,
                          color: AppColors.danger,
                          size: 20),
                      const SizedBox(
                          width: AppSpacing.sm),
                      Expanded(
                          child: Text(
                              'سبب الرفض: ${inv.rejectionReason}')),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              // طلب واحد مجمع للمدير: الحجز + الناقص + العربون + التوريد الجاهز.
              // نسخة الجهاز: مخفية (لا توريد ولا موافقات — حفظ مباشر).
              if (!isLocal &&
                  (inv.status == 'DRAFT' ||
                      inv.status == 'PENDING_APPROVAL' ||
                      inv.status == 'REJECTED'))
                _ReservationSection(invoice: inv),
              if (!isLocal &&
                  (inv.status == 'DRAFT' ||
                      inv.status == 'PENDING_APPROVAL' ||
                      inv.status == 'REJECTED'))
                const SizedBox(height: AppSpacing.md),
              _ActionsCard(
                status: inv.status,
                paymentStatus: inv.paymentStatus,
                canSubmit: canSubmit,
                pending: pending,
                canApprove: canApprove,
                isMine: isMine,
                isCompanyManager: isCompanyManager,
                canRegisterSerial: canRegisterSerial,
                isLocal: isLocal,
                onSubmit: () =>
                    _submitInvoice(context, ref, inv),
                onApprove: () => _act(
                    context,
                    ref,
                    () => ref
                        .read(salesRepositoryProvider)
                        .approve(inv.id)),
                onApproveDirect: () =>
                    _approveDirectLocal(context, ref, inv),
                onReject: () =>
                    _rejectSheet(context, ref, inv.id),
                onShare: () => _share(context, ref, inv),
                onPrintPdf: () =>
                    _printPdf(context, ref, inv),
                onReceipt: supportsUsbReceiptPrint
                    ? () => _printReceipt(context, ref, inv)
                    : null,
                invoiceId: inv.id,
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: AttachmentsSection(
                    entityType: 'SALES_INVOICE',
                    entityId: inv.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitInvoice(BuildContext context,
      WidgetRef ref, SalesInvoice inv) async {
    final id = inv.id;
    // فحص الناقص قبل الإرسال (نفس دورة الفورم): حجز + توريد تلقائي.
    var autoSupply = false;
    try {
      if (inv.warehouseId != null) {
        final rows =
            await ref.read(salesItemsProvider(id).future);
        final lines = [
          for (final r in rows)
            if (!r.isCustom && r.productId != null)
              ShortageLine(
                  productId: r.productId,
                  name: r.itemName,
                  qty: r.quantity),
        ];
        final exceeding =
            await findExceeding(ref.read, inv.warehouseId!, lines);
        if (exceeding.isNotEmpty && context.mounted) {
          final choice =
              await showShortageDialog(context, exceeding);
          if (choice == ShortageChoice.cancel) return;
          if (choice == ShortageChoice.adjust) {
            final repo = ref.read(salesRepositoryProvider);
            for (final e in exceeding) {
              final row = rows.firstWhere(
                  (r) => r.productId == e.line.productId);
              await repo.updateItem(
                itemId: row.id,
                invoiceId: id,
                quantity: e.available,
              );
            }
            ref
              ..invalidate(salesDetailProvider(id))
              ..invalidate(salesItemsProvider(id));
          } else {
            autoSupply = true;
          }
        }
      }
    } catch (_) {}
    try {
      await ref.read(salesRepositoryProvider).submit(id);
      // الأصناف الخاصة → طلبات تصنيع تلقائية.
      final mfgCount =
          await ensureCustomizedForInvoice(ref, id);
      var supplied = 0;
      if (autoSupply && inv.warehouseId != null) {
        final rows =
            await ref.read(salesItemsProvider(id).future);
        supplied = await autoSupplyRequest(ref.read,
            invoiceId: id,
            warehouseId: inv.warehouseId!,
            lines: [
              for (final r in rows)
                if (!r.isCustom && r.productId != null)
                  ShortageLine(
                      productId: r.productId,
                      name: r.itemName,
                      qty: r.quantity),
            ]);
      }
      ref
        ..invalidate(salesDetailProvider(invoiceId))
        ..invalidate(salesItemsProvider(invoiceId))
        ..invalidate(salesPageProvider);
      if (context.mounted) {
        final msgs = <String>[];
        if (mfgCount > 0) {
          msgs.add(
              'واتنشأ $mfgCount طلب تصنيع للأصناف الخاصة');
        }
        if (supplied > 0) {
          msgs.add(
              'واتعمل $supplied طلب توريد بالناقص وراح لاعتماد المدير');
        }
        if (msgs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'تم الإرسال للاعتماد، ${msgs.join('، ')}.')));
        }
        // العربون للآجل أو الصنف الخاص فقط — مش للكاش.
        var hasCustom = mfgCount > 0;
        if (!hasCustom) {
          try {
            hasCustom = (await ref
                    .read(salesItemsProvider(id).future))
                .any((r) => r.isCustom);
          } catch (_) {}
        }
        if (!context.mounted) return;
        final isCredit =
            (inv.paymentMethodCode ?? '') == 'CREDIT';
        if (isCredit || hasCustom) {
          await depositPrompt(context, id);
        } else {
          context.pop();
        }
      }
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
  /// + اعتماد + خصم فوري من المخزون بدون موافقات.
  /// الشحن: اعتماد فقط (الحجز) — أنشئ الشحنة واشحنها من
  /// شاشة الشحن (بيانات المستلم غير متوفرة هنا).
  Future<void> _approveDirectLocal(BuildContext context,
      WidgetRef ref, SalesInvoice inv) async {
    final id = inv.id;
    final repo = ref.read(salesRepositoryProvider);
    try {
      if (inv.status == 'DRAFT' || inv.status == 'REJECTED') {
        await repo.submit(id);
      }
      await repo.approve(id);
      var isShipping = false;
      try {
        final raw =
            await ref.read(salesRepositoryProvider).getRawById(id);
        isShipping =
            '${raw?['delivery_method'] ?? ''}' == 'SHIPPING';
      } catch (_) {}
      if (!isShipping) {
        await repo.fulfill(id);
      }
      ref
        ..invalidate(salesDetailProvider(invoiceId))
        ..invalidate(salesItemsProvider(invoiceId))
        ..invalidate(salesPageProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isShipping
                ? 'تم الاعتماد وحجز المخزون — أنشئ الشحنة واشحنها من شاشة الشحن ليتم الخصم.'
                : 'تم الاعتماد وخصم المخزون.')));
        context.pop();
      }
    } catch (e) {
      ref
        ..invalidate(salesDetailProvider(invoiceId))
        ..invalidate(salesItemsProvider(invoiceId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(salesDetailProvider(invoiceId))
        ..invalidate(salesItemsProvider(invoiceId))
        ..invalidate(salesPageProvider);
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

  /// بيانات PDF فاتورة المبيعات — مشتركة بين المشاركة والطباعة
  /// عشان الزرارين يطلعوا نفس الشكل بالظبط.
  InvoicePdfData _salesPdfData(
      SalesInvoice inv, List<SalesInvoiceItem> rows) {
    return InvoicePdfData(
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
      notes: inv.rejectionReason != null
          ? 'سبب الرفض: ${inv.rejectionReason}'
          : null,
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref,
      SalesInvoice inv) async {
    try {
      final rows =
          await ref.read(salesItemsProvider(inv.id).future);
      if (!context.mounted) return;
      await shareInvoicePdf(
        context,
        _salesPdfData(inv, rows),
      );
    } catch (e, st) {
      debugPrint('share sales pdf error: $e (${e.runtimeType})\n$st');
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
      SalesInvoice inv) async {
    try {
      final rows =
          await ref.read(salesItemsProvider(inv.id).future);
      if (!context.mounted) return;
      await printInvoicePdf(
        context,
        _salesPdfData(inv, rows),
      );
    } catch (e, st) {
      debugPrint('print sales pdf error: $e (${e.runtimeType})\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تعذر تجهيز الطباعة.')));
      }
    }
  }

  /// طباعة الفاتورة على طابعة الريسيت الحراري USB (لينكس).
  Future<void> _printReceipt(BuildContext context, WidgetRef ref,
      SalesInvoice inv) async {
    try {
      final rows =
          await ref.read(salesItemsProvider(inv.id).future);
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
          title: 'فاتورة مبيعات',
          number: inv.number,
          date: inv.createdAt,
          partnerLabel: 'العميل',
          partnerName: inv.customerName ?? 'عميل نقدي',
          paymentLabel: inv.paymentMethodName,
          rows: [
            for (final it in rows)
              ReceiptInvoiceRow(
                name:
                    '${it.isCustom ? '🔧 ' : ''}${it.itemName}${it.isCustom && it.specSummary.isNotEmpty ? ' (${it.specSummary})' : ''}',
                qty: it.quantity,
                price: it.unitPrice,
                total: it.total,
                discount: it.discount,
                taxRate: it.taxRate,
              ),
          ],
          subtotal: inv.subtotal,
          discount: inv.discount,
          taxAmount: inv.taxAmount,
          total: inv.grandTotal,
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
        padding: const EdgeInsets.all(AppSpacing.mdx),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Text('سبب الرفض *',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
                controller: ctrl,
                decoration:
                    const InputDecoration(labelText: 'السبب')),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop();
                await _act(
                    context,
                    ref,
                    () => ref
                        .read(salesRepositoryProvider)
                        .reject(id, ctrl.text.trim()));
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String number;
  final String status;
  final DateTime date;
  final String? reference;
  const _HeaderCard({
    required this.number,
    required this.status,
    required this.date,
    this.reference,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(number,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall),
                Text(AppFormat.dateTime(date),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall),
              ],
            ),
          ),
          AppStatus.badge(status),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _InfoRow(
      {required this.label,
      required this.value,
      this.bold = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: bold
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium)),
          Flexible(
            child: Text(
              value,
              style: bold
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// ربح الفاتورة = (سعر البيع - الخصم) - (تكلفة الشراء)، بدون ضريبة وبدون مصاريف.
class _InvoiceProfitCard extends ConsumerWidget {
  final String invoiceId;
  const _InvoiceProfitCard({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(salesItemsProvider(invoiceId));
    final canEditCost =
        ref.watch(myPermissionsProvider).maybeWhen(
              data: (p) => p.can(Permissions.salesEdit),
              orElse: () => false,
            );
    return itemsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        var saleNet = 0.0;
        var cost = 0.0;
        for (final r in rows) {
          saleNet += r.quantity * r.unitPrice - r.discount;
          cost += r.quantity * r.unitCost;
        }
        final profit = saleNet - cost;
        final hasCost = rows.any((r) => r.unitCost > 0);
        final customs = [
          for (final r in rows)
            if (r.isCustom) r
        ];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'ربح الفاتورة'),
              _InfoRow(
                  label: 'البيع (بدون ضريبة)',
                  value: AppFormat.money(saleNet)),
              _InfoRow(
                  label: 'تكلفة الشراء',
                  value: hasCost
                      ? AppFormat.money(cost)
                      : 'تظهر بعد الاعتماد'),
              const Divider(),
              _InfoRow(
                label: 'صافي ربح الفاتورة',
                value: AppFormat.money(profit),
                bold: true,
              ),
              // تكلفة الأصناف الخاصة (تتعدل حتى بعد الاعتماد).
              for (final c in customs)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '🔧 ${c.itemName}: شراء ${AppFormat.money(c.unitCost)} × ${c.quantity}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                        ),
                      ),
                      if (canEditCost)
                        TextButton(
                          onPressed: () =>
                              _editCostSheet(
                                  context, ref, c),
                          child:
                              const Text('تعديل'),
                        ),
                    ],
                  ),
                ),
              const Text(
                'الربح = (سعر البيع - الخصم) - تكلفة الشراء، بدون ضريبة وبدون مصاريف.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editCostSheet(
      BuildContext context,
      WidgetRef ref,
      SalesInvoiceItem item) async {
    final ctrl = TextEditingController(
        text: item.unitCost.toString());
    final saved = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                    16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Text('تكلفة الشراء: ${item.itemName}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType
                  .numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText:
                      'سعر الشراء * (تكلفة الوحدة)'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(
                    ctrl.text.trim());
                if (v == null || v < 0) return;
                Navigator.of(ctx).pop(v);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (saved == null || !context.mounted) return;
    try {
      await ref.read(salesRepositoryProvider).updateItemCost(
            itemId: item.id,
            unitCost: saved,
          );
      ref
        ..invalidate(salesItemsProvider(invoiceId))
        ..invalidate(salesDetailProvider(invoiceId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'اتحفظت التكلفة والربح اتظبط.')));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حفظ التكلفة.')));
    }
  }
}

class _ActionsCard extends StatelessWidget {
  final String status;
  final String paymentStatus;
  final bool canSubmit;
  final bool pending;
  final bool canApprove;
  final bool isMine;
  final bool isCompanyManager;
  final bool canRegisterSerial;
  final bool isLocal;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final VoidCallback onApproveDirect;
  final VoidCallback onReject;
  final VoidCallback onShare;
  final VoidCallback onPrintPdf;
  final VoidCallback? onReceipt;
  final String invoiceId;
  const _ActionsCard({
    required this.status,
    this.paymentStatus = 'UNPAID',
    required this.canSubmit,
    required this.pending,
    required this.canApprove,
    required this.isMine,
    required this.isCompanyManager,
    this.canRegisterSerial = false,
    this.isLocal = false,
    required this.onSubmit,
    required this.onApprove,
    required this.onApproveDirect,
    required this.onReject,
    required this.onShare,
    required this.onPrintPdf,
    this.onReceipt,
    required this.invoiceId,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'الإجراءات'),
          // الخياران جنب بعض: طباعة PDF (كل المنصات) + ريسيت (لينكس).
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: onPrintPdf,
                icon: const Icon(Icons.print_outlined,
                    size: 18),
                label: const Text('طباعة PDF'),
              ),
              OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined,
                    size: 18),
                label: const Text('مشاركة PDF'),
              ),
              if (onReceipt != null)
                FilledButton.tonalIcon(
                  onPressed: onReceipt,
                  icon: const Icon(
                      Icons.receipt_long_outlined,
                      size: 18),
                  label: const Text('طباعة ريسيت'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // نسخة الجهاز: اعتماد وخصم مباشر بدون موافقات.
          if (isLocal && (canSubmit || pending))
            FilledButton.icon(
              onPressed: onApproveDirect,
              style: FilledButton.styleFrom(
                  backgroundColor:
                      AppColors.success),
              icon: const Icon(
                  Icons.check_circle_outline,
                  size: 18),
              label: const Text(
                  'حفظ واعتماد (خصم المخزون فوري)'),
            ),
          if (!isLocal && canSubmit)
            FilledButton(
              onPressed: onSubmit,
              child: const Text('إرسال للاعتماد'),
            ),
          if (!isLocal &&
              pending &&
              canApprove &&
              (!isMine || isCompanyManager)) ...[
            FilledButton(
              onPressed: onApprove,
              style: FilledButton.styleFrom(
                  backgroundColor:
                      AppColors.success),
              child:
                  const Text('اعتماد (حجز المخزون)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onReject,
              child: const Text('رفض بسبب'),
            ),
          ],
          if (!isLocal && pending && isMine && !isCompanyManager)
            const Text(
                'فاتورتك بانتظار الاعتماد — لا يمكنك اعتمادها بنفسك.',
                textAlign: TextAlign.center),
          if (!isLocal && pending && !canApprove)
            const Text(
                'الفاتورة قيد المراجعة — الاعتماد للمدير فقط.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey)),
          if (status == 'APPROVED') ...[
            if (paymentStatus != 'PAID')
              OutlinedButton(
                onPressed: () => context.push(
                    '/payments/new?sales=$invoiceId'),
                child: const Text('تسجيل دفعة (عربون / تحصيل آجل)'),
              ),
            if (paymentStatus == 'PAID')
              const Text(
                'مدفوعة بالكامل — لا مستحقات عليها.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.green, fontSize: 12),
              ),
            if (paymentStatus != 'PAID')
              const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => context.push(
                  '/sales-returns/new?invoice=$invoiceId'),
              child: const Text('مرتجع مبيعات'),
            ),
            // تسجيل السيريالات: مخفي عن منشئ الفاتورة دائما
            // (حتى المدير) — نفس روح منع الاعتماد الذاتي.
            if (canRegisterSerial && !isMine) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () =>
                    showRegisterSerialSheet(
                        context, invoiceId),
                icon: const Icon(
                    Icons.barcode_reader,
                    size: 18),
                label: const Text(
                    'تسجيل سيريالات البيع'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// محرر المسودة: تعديل السعر/الكمية/الضريبة + حذف + إضافة صنف.
/// أي تعديل يحدث sales_invoice_items فقط + recalc للإجماليات،
/// ولا يمس products.sale_price ولا warehouse_stock.
class _DraftItemsEditor extends ConsumerStatefulWidget {
  final String invoiceId;
  const _DraftItemsEditor({required this.invoiceId});

  @override
  ConsumerState<_DraftItemsEditor> createState() =>
      _DraftItemsEditorState();
}

class _DraftItemsEditorState
    extends ConsumerState<_DraftItemsEditor> {
  bool _busy = false;
  // ضريبة عامة على الفاتورة كلها.
  bool _hasTax = false;
  final _taxCtrl = TextEditingController(text: '14');
  bool _taxInit = false;

  @override
  void dispose() {
    _taxCtrl.dispose();
    super.dispose();
  }

  void _initTaxFromRows(List<SalesInvoiceItem> rows) {
    if (_taxInit) return;
    _taxInit = true;
    final withTax = rows.where((r) => r.taxRate > 0).toList();
    if (withTax.isNotEmpty) {
      _hasTax = true;
      // لو كلها نفس النسبة اعرضها، غير كده اعرض أول قيمة.
      final first = withTax.first.taxRate;
      final same = withTax.every((r) => (r.taxRate - first).abs() < 1e-9);
      _taxCtrl.text =
          (same ? first : withTax.map((r) => r.taxRate).reduce((a, b) => a > b ? a : b))
              .toString();
    }
  }

  double get _effectiveTax {
    if (!_hasTax) return 0;
    return double.tryParse(_taxCtrl.text.trim()) ?? 0;
  }

  void _refresh() {
    ref
      ..invalidate(salesDetailProvider(widget.invoiceId))
      ..invalidate(salesItemsProvider(widget.invoiceId));
  }

  Future<void> _updateQty(String itemId, double qty) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).updateItem(
            itemId: itemId,
            invoiceId: widget.invoiceId,
            quantity: qty,
          );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حفظ التعديل.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRow(String itemId, double price) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).updateItem(
            itemId: itemId,
            invoiceId: widget.invoiceId,
            unitPrice: price,
          );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حفظ التعديل.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تطبيق نسبة الضريبة العامة على كل الأصناف دفعة واحدة.
  Future<void> _applyTaxToAll(List<SalesInvoiceItem> rows) async {
    if (_busy) return;
    final target = _effectiveTax.clamp(0, 100).toDouble();
    final dirty = rows
        .where((r) => (r.taxRate - target).abs() > 1e-9)
        .toList();
    if (dirty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الضريبة مطبقة بالفعل.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      for (final r in dirty) {
        await repo.updateItem(
          itemId: r.id,
          invoiceId: widget.invoiceId,
          taxRate: target,
        );
      }
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(target == 0
                ? 'تم إلغاء الضريبة من كل الأصناف.'
                : 'تم تطبيق ضريبة $target% على كل الأصناف.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر تطبيق الضريبة.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String itemId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(salesRepositoryProvider)
          .removeItem(itemId, widget.invoiceId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حذف الصنف.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickProduct() async {
    final q = TextEditingController();
    List<dynamic> results = [];
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('إضافة صنف (سعر البيع فقط)',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث بالاسم / SKU'))),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(productsRepositoryProvider)
                        .search(query: q.text, pageSize: 20);
                    setS(() {});
                  },
                ),
              ]),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in results)
                      ListTile(
                        title: Text((p as dynamic).name as String),
                        subtitle: Text(
                          '${(p as dynamic).sku} • سعر البيع: ${AppFormat.money((p as dynamic).salePrice)}',
                          textDirection: TextDirection.ltr,
                        ),
                        trailing: TextButton(
                          child: const Text('إضافة'),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            setState(() => _busy = true);
                            try {
                              await ref
                                  .read(salesRepositoryProvider)
                                  .addItems(widget.invoiceId, [
                                SalesItemInput(
                                  productId: (p as dynamic).id as String?,
                                  itemName:
                                      (p as dynamic).name as String,
                                  sku: (p as dynamic).sku as String?,
                                  quantity: 1,
                                  unitPrice:
                                      ((p as dynamic).salePrice as double),
                                  taxRate: _effectiveTax,
                                ),
                              ]);
                              _refresh();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      content: Text(e is AppFailure
                                          ? e.messageAr
                                          : 'تعذر إضافة الصنف.')));
                            } finally {
                              if (mounted) {
                                setState(() => _busy = false);
                              }
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(salesItemsProvider(widget.invoiceId));
    return items.when(
      loading: () => const LoadingSkeleton(rows: 3),
      error: (_, _) =>
          const ErrorState(message: 'تعذر تحميل الأصناف.'),
      data: (rows) {
        _initTaxFromRows(rows);
        return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'مسودة — تقدر تعدل السعر والكمية، ويسمع في الإجماليات فوراً بدون ما يغير سعر المخزون.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 4),
            child: Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('يوجد ضريبة؟'),
                  value: _hasTax,
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _hasTax = v ?? false),
                ),
                if (_hasTax)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _taxCtrl,
                          enabled: !_busy,
                          keyboardType: const TextInputType
                              .numberWithOptions(
                                  decimal: true),
                          textDirection:
                              TextDirection.ltr,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'نسبة الضريبة % (تطبق على كل الأصناف)',
                            isDense: true,
                          ),
                          onChanged: (_) =>
                              setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                _applyTaxToAll(rows),
                        child: const Text('تطبيق'),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final it in rows)
            _DraftRowCard(
              key: ValueKey('draft-row-${it.id}'),
              item: it,
              busy: _busy,
              onDec: it.quantity <= 1
                  ? null
                  : () => _updateQty(it.id, it.quantity - 1),
              onInc: () => _updateQty(it.id, it.quantity + 1),
              onSave: (price) => _saveRow(it.id, price),
              onRemove: () => _remove(it.id),
            ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickProduct,
            icon: const Icon(Icons.add_outlined, size: 18),
            label: const Text('إضافة صنف بسعر البيع'),
          ),
        ],
        );
      },
    );
  }
}

/// طلب واحد مجمع للمدير (بدل ما يتوه بين طلبين):
/// الفاتورة بكام + مدفوع مقدم كام + ناقص كام + طلب التوريد جاهز
/// (اعتماد/استلام/واتساب) — كله في شاشة الفاتورة.
class _ReservationSection extends ConsumerWidget {
  final SalesInvoice invoice;
  const _ReservationSection({required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(salesItemsProvider(invoice.id));
    final paid = ref.watch(_detailPaidProvider(invoice.id));
    final supply = ref.watch(linkedSupplyProvider(invoice.id));
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canManageSupply = perms.can(Permissions.purchasesApprove) ||
        perms.can(Permissions.purchasesCreate) ||
        perms.can(Permissions.purchasesEdit);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
              title: 'الحجز والنواقص والتوريد'),
          items.when(
            loading: () =>
                const LoadingSkeleton(rows: 2),
            error: (_, _) => const Text(
                'تعذر تحميل بنود الحجز.'),
            data: (rows) {
              final std = [
                for (final r in rows)
                  if (!r.isCustom &&
                      r.productId != null)
                    r
              ];
              if (std.isEmpty) {
                return const Text(
                  'لا توجد أصناف مخزنية — لا حجز مطلوب.',
                  style: TextStyle(
                      color: Colors.grey),
                );
              }
              final paidVal = paid.maybeWhen(
                data: (v) => v,
                orElse: () => 0.0,
              );
              final rest =
                  invoice.grandTotal - paidVal;
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  _InfoRow(
                      label: 'الفاتورة بكام',
                      value: AppFormat.money(
                          invoice.grandTotal),
                      bold: true),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoRow(
                            label:
                                'مدفوع مقدم (حجز)',
                            value: paid.maybeWhen(
                              data: (v) =>
                                  AppFormat.money(v),
                              orElse: () => '…',
                            ),
                            bold: true),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push(
                            '/payments/new?sales=${invoice.id}'),
                        icon: const Icon(
                            Icons.payments_outlined,
                            size: 18),
                        label:
                            const Text('تسجيل دفعة'),
                      ),
                    ],
                  ),
                  _InfoRow(
                      label: 'المتبقي',
                      value: AppFormat.money(
                          rest < 0 ? 0 : rest)),
                  const Divider(height: 20),
                  const Text(
                    'الأصناف: المطلوب / المتاح / الناقص',
                    style: TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  for (final r in std)
                    _ResLineTile(
                      item: r,
                      warehouseId:
                          invoice.warehouseId,
                    ),
                  const Divider(height: 20),
                  const Text(
                    'طلب التوريد الجاهز',
                    style: TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  supply.when(
                    loading: () => const Center(
                        child: SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(
                                    strokeWidth:
                                        2))),
                    error: (_, _) =>
                        const Text(
                            'تعذر تحميل طلبات التوريد.'),
                    data: (reqs) {
                      if (reqs.isEmpty) {
                        return OutlinedButton.icon(
                          onPressed: () =>
                              _prepareSupply(
                                  context, ref),
                          icon: const Icon(
                              Icons
                                  .local_shipping_outlined,
                              size: 18),
                          label: const Text(
                              'تجهيز طلب التوريد الآن'),
                        );
                      }
                      return Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                        children: [
                          for (final q in reqs)
                            _SupplyCard(
                              request: q,
                              invoiceWarehouseId:
                                  invoice.warehouseId,
                              canManageSupply:
                                  canManageSupply,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _prepareSupply(
      BuildContext context, WidgetRef ref) async {
    final whId = invoice.warehouseId;
    if (whId == null) return;
    try {
      final rows =
          await ref.read(salesItemsProvider(invoice.id).future);
      final n = await autoSupplyRequest(ref.read,
          invoiceId: invoice.id,
          warehouseId: whId,
          lines: [
            for (final r in rows)
              if (!r.isCustom &&
                  r.productId != null)
                ShortageLine(
                    productId: r.productId,
                    name: r.itemName,
                    qty: r.quantity),
          ]);
      ref.invalidate(linkedSupplyProvider(invoice.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(n > 0
                    ? 'اتجهز $n طلب توريد وراح لاعتماد المدير.'
                    : 'لا يوجد ناقص يستدعي طلب توريد.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'تعذر تجهيز طلب التوريد.')));
      }
    }
  }
}

/// سطر صنف: المطلوب + المتاح في مخزن الفاتورة + الناقص + كل المخازن.
class _ResLineTile extends ConsumerWidget {
  final SalesInvoiceItem item;
  final String? warehouseId;
  const _ResLineTile(
      {required this.item, required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whAvail = warehouseId == null
        ? null
        : ref.watch(
            _detailAvailProvider(warehouseId!));
    final allStock = item.productId == null
        ? null
        : ref.watch(
            _detailLineStockProvider(item.productId!));
    final a = whAvail?.maybeWhen(
      data: (m) => m[item.productId],
      orElse: () => null,
    );
    final missing =
        a == null ? null : item.quantity - a;
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.itemName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold)),
          Text(
            'المطلوب: ${item.quantity}'
            '${a == null ? '' : ' • المتاح (مخزن الفاتورة): $a'}'
            '${missing == null ? '' : missing > 0 ? ' • الناقص: $missing' : ' • متوفر ✓'}',
            style: TextStyle(
                fontSize: 13,
                color: missing != null && missing > 0
                    ? Colors.deepOrange
                    : null,
                fontWeight:
                    missing != null && missing > 0
                        ? FontWeight.bold
                        : FontWeight.normal),
          ),
          if (allStock != null)
            allStock.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) =>
                  const SizedBox.shrink(),
              data: (lines) {
                if (lines.isEmpty) {
                  return const Text(
                    'لا رصيد في أي مخزن.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey),
                  );
                }
                return Text(
                  'كل المخازن: ${lines.map((l) => '${l.warehouseName}: ${l.available}').join(' • ')}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// كارت طلب توريد مربوط: الحالة + الأصناف + إجراءات سريعة
/// (اعتماد/استلام الكل/التفاصيل للواتساب والـ PDF والتعديل).
class _SupplyCard extends ConsumerWidget {
  final ProcurementRequest request;
  final String? invoiceWarehouseId;
  final bool canManageSupply;
  const _SupplyCard({
    required this.request,
    required this.invoiceWarehouseId,
    required this.canManageSupply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(procurementItemsProvider(request.id));
    final pending =
        request.status == 'PENDING_APPROVAL';
    final receivable = request.status == 'APPROVED' ||
        request.status == 'PARTIALLY_RECEIVED';
    return Card(
      color: Colors.orange.shade50,
      margin:
          const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request.number} • ${request.supplierName ?? 'بدون مورد'}',
                    textDirection:
                        TextDirection.ltr,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold),
                  ),
                ),
                AppStatus.badge(request.status),
              ],
            ),
            items.when(
              loading: () => const Text('…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey)),
              error: (_, _) =>
                  const SizedBox.shrink(),
              data: (rows) => Text(
                rows
                    .map((it) =>
                        '${it.productName ?? 'صنف'}: مطلوب ${it.requested} / مستلم ${it.received}')
                    .join('\n'),
                style: const TextStyle(
                    fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (pending && canManageSupply)
                  FilledButton.tonal(
                    onPressed: () => _act(
                        context,
                        ref,
                        () => ref
                            .read(
                                procurementRepositoryProvider)
                            .approve(request.id),
                        'تم اعتماد طلب التوريد.'),
                    child:
                        const Text('اعتماد التوريد'),
                  ),
                if (receivable && canManageSupply)
                  FilledButton.tonal(
                    onPressed: () =>
                        _receiveAll(context, ref),
                    child: const Text(
                        'استلام الكل (تنفيذ)'),
                  ),
                OutlinedButton(
                  onPressed: () => context.push(
                      '/procurement/${request.id}'),
                  child:
                      const Text('التفاصيل (تعديل/واتساب/PDF)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(
      BuildContext context,
      WidgetRef ref,
      Future<void> Function() fn,
      String okMsg) async {
    try {
      await fn();
      ref.invalidate(linkedSupplyProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'حدث خطأ أثناء تنفيذ العملية.')));
      }
    }
  }

  /// استلام كل المتبقي في مخزن الفاتورة بضغطة واحدة.
  Future<void> _receiveAll(
      BuildContext context, WidgetRef ref) async {
    final whId = invoiceWarehouseId;
    if (whId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'فاتورة بلا مخزن — الاستلام من صفحة الطلب.')));
      return;
    }
    try {
      final rows = await ref
          .read(procurementRepositoryProvider)
          .itemsOf(request.id);
      final lines = <Map<String, dynamic>>[];
      for (final it in rows) {
        final rem = it.remaining;
        if (rem > 0) {
          lines.add({'item_id': it.id, 'qty': rem});
        }
      }
      if (lines.isEmpty) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الاستلام'),
          content: Text(
              'استلام كل المتبقي (${lines.length} صنف) في مخزن الفاتورة؟ الزيادة هتفضل في المخزن.'),
          actions: [
            TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(true),
                child: const Text('استلام وتنفيذ')),
          ],
        ),
      );
      if (ok != true) return;
      await ref
          .read(procurementRepositoryProvider)
          .receive(request.id, lines, 'استلام من شاشة الفاتورة',
              warehouseId: whId);
      ref.invalidate(linkedSupplyProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'تم الاستلام — اعتمد الفاتورة لحجز المخزون للزبون.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'تعذر الاستلام — تحقق من الكميات.')));
      }
    }
  }
}

final _detailPaidProvider =
    FutureProvider.autoDispose.family<double, String>((ref, id) {
  return ref.watch(procurementRepositoryProvider).invoicePaid(id);
});

final _detailAvailProvider = FutureProvider.autoDispose
    .family<Map<String, double>, String>((ref, warehouseId) {
  return fetchAvailability(ref.read, warehouseId);
});

final _detailLineStockProvider = FutureProvider.autoDispose
    .family<List<dynamic>, String>((ref, productId) {
  return ref
      .watch(warehousesRepositoryProvider)
      .stockOfProduct(productId);
});

/// كارت سطر واحد في المسودة: تعديل سعر البيع فقط + زرار حفظ صريح.
/// الضريبة بقت عامة على الفاتورة كلها من الكارت اللي فوق.
class _DraftRowCard extends StatefulWidget {
  final SalesInvoiceItem item;
  final bool busy;
  final VoidCallback? onDec;
  final VoidCallback? onInc;
  final ValueChanged<double> onSave;
  final VoidCallback onRemove;
  const _DraftRowCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onDec,
    required this.onInc,
    required this.onSave,
    required this.onRemove,
  });

  @override
  State<_DraftRowCard> createState() => _DraftRowCardState();
}

class _DraftRowCardState extends State<_DraftRowCard> {
  late final TextEditingController _priceCtrl;
  final _priceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _priceCtrl =
        TextEditingController(text: widget.item.unitPrice.toString());
  }

  @override
  void didUpdateWidget(covariant _DraftRowCard old) {
    super.didUpdateWidget(old);
    // زامن مع السيرفر فقط لو الحقل مش عليه فوكس عشان متقطعش الكتابة.
    if (old.item.id != widget.item.id) {
      _priceCtrl.text = widget.item.unitPrice.toString();
    } else {
      if (!_priceFocus.hasFocus &&
          _priceCtrl.text != widget.item.unitPrice.toString()) {
        _priceCtrl.text = widget.item.unitPrice.toString();
      }
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  double? get _parsedPrice => double.tryParse(_priceCtrl.text.trim());

  bool get _validPrice =>
      _parsedPrice != null && _parsedPrice! >= 0;

  bool get _dirty =>
      _validPrice &&
      (_parsedPrice! - widget.item.unitPrice).abs() > 1e-9;

  void _submit() {
    if (!_validPrice || !_dirty || widget.busy) return;
    widget.onSave(_parsedPrice!);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(it.itemName,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall),
              ),
              Text(AppFormat.money(it.total),
                  style:
                      Theme.of(context).textTheme.labelLarge),
              IconButton(
                iconSize: 20,
                tooltip: 'حذف الصنف',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger),
                onPressed: widget.busy ? null : widget.onRemove,
              ),
            ],
          ),
          Text(
            '${it.isCustom ? '🔧 ' : ''}${it.quantity} × ${AppFormat.money(it.unitPrice)} • ضريبة ${it.taxRate}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (it.isCustom && it.specSummary.isNotEmpty)
            Text(
              it.specSummary,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    visualDensity: VisualDensity.compact,
                    icon:
                        const Icon(Icons.remove_outlined),
                    onPressed:
                        widget.busy ? null : widget.onDec,
                  ),
                  Text('${it.quantity}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall),
                  IconButton(
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_outlined),
                    onPressed:
                        widget.busy ? null : widget.onInc,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  focusNode: _priceFocus,
                  enabled: !widget.busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'سعر البيع',
                    isDense: true,
                    errorText: _priceCtrl.text.isEmpty ||
                            _validPrice
                        ? null
                        : 'رقم غير صالح',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed:
                    (_validPrice && _dirty && !widget.busy)
                        ? _submit
                        : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: widget.busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Text('حفظ'),
              ),
            ],
          ),
          if (_dirty && _validPrice)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('دوس حفظ عشان يسمع في الإجماليات.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
