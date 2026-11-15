import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/pdf/invoice_pdf.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../data/customized_from_invoice.dart';
import '../../data/manufacturing_repository.dart';
import '../../domain/manufacturing.dart';
import '../providers/manufacturing_providers.dart';
import 'manufacturing_hub_screen.dart' show czStatusAr;

class CustomizedDetailScreen extends ConsumerWidget {
  final String itemId;
  const CustomizedDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(czDetailProvider(itemId));
    final myId =
        ref.watch(authRepositoryProvider).currentUser?.id;
    final canApprove = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.salesApprove),
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
        data: (c) {
          if (c == null) {
            return const Center(child: Text('الصنف غير موجود.'));
          }
          final isMine = c.createdBy != null && c.createdBy == myId;
          final draft =
              c.status == 'DRAFT' || c.status == 'REJECTED';
          final pending = c.status == 'PENDING_APPROVAL';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(c.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text(c.code, textDirection: TextDirection.ltr),
              Text(
                  '${czStatusAr(c.status)} • ${AppFormat.money(c.quantity, suffix: '')} × ${AppFormat.money(c.unitPrice)} = ${AppFormat.money(c.totalPrice)}'),
              if (c.fromSalesInvoice) ...[
                const SizedBox(height: AppSpacing.sm),
                _InvoiceSourceCard(
                    invoiceId: c.salesInvoiceId!),
              ],
              if (c.specSummary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                          title: 'مواصفات التصنيع'),
                      _SpecRow(
                          label: 'المقاس',
                          value: (c.length != null &&
                                  c.width != null)
                              ? '${_f(c.length!)} × ${_f(c.width!)} ${c.lengthUnit ?? c.widthUnit ?? ''}'
                                  .trim()
                              : '—'),
                      _SpecRow(
                          label: 'المادة الخام',
                          value: c.rawMaterial ??
                              '—'),
                      if (c.qtyPerRoll != null)
                        _SpecRow(
                            label: 'Qty/Roll',
                            value: _f(c.qtyPerRoll!)),
                      if (c.unit != null)
                        _SpecRow(
                            label: 'الوحدة',
                            value: c.unit!),
                      _SpecRow(
                          label: 'سعر البيع',
                          value:
                              '${AppFormat.money(c.unitPrice)} / ${c.unit ?? 'وحدة'}'),
                      if (c.createdByName != null)
                        _SpecRow(
                            label: 'أنشأ الطلب',
                            value: c.createdByName!),
                    ],
                  ),
                ),
              ],
              if (c.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(c.description!),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _share(context, ref, c),
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    size: 18),
                label: const Text('PDF'),
              ),
              const SizedBox(height: 8),
              if (draft)
                FilledButton(
                  onPressed: () => _act(
                      context,
                      ref,
                      () => ref
                          .read(manufacturingRepositoryProvider)
                          .submitCustomized(c.id)),
                  child: const Text('إرسال للاعتماد'),
                ),
              if (pending &&
                  canApprove &&
                  (!isMine || isCompanyManager))
                FilledButton(
                  onPressed: () =>
                      _approve(context, ref, c.id),
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          AppColors.success),
                  child: const Text('موافقة'),
                ),
              if (pending &&
                  canApprove &&
                  (!isMine || isCompanyManager))
                OutlinedButton(
                  onPressed: () =>
                      _rejectSheet(context, ref, c.id),
                  child: const Text('رفض'),
                ),
              if (pending && isMine && !isCompanyManager)
                const Text(
                    'صنفك بانتظار الاعتماد — لا يمكنك اعتماده بنفسك.',
                    textAlign: TextAlign.center),
              if (pending && !canApprove)
                const Text(
                    'الصنف قيد المراجعة — الاعتماد للمدير فقط.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              if (c.status == 'APPROVED')
                FilledButton.tonal(
                  onPressed: () => context.push(
                      '/manufacturing-orders/new?cz=${c.id}'),
                  child: const Text('إنشاء أمر إنتاج'),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _f(double v) =>
      v == v.truncateToDouble() ? v.truncate().toString() : v.toString();

  /// اعتماد + إنشاء أمر التصنيع تلقائيا.
  Future<void> _approve(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      final msg =
          await approveCustomizedAndMakeOrder(ref, id);
      ref
        ..invalidate(czDetailProvider(id))
        ..invalidate(czPageProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg ?? 'تمت الموافقة وإنشاء أمر التصنيع.')));
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء تنفيذ العملية.')));
    }
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(czDetailProvider(itemId))
        ..invalidate(czPageProvider);
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

  Future<void> _share(
      BuildContext context, WidgetRef ref, CustomizedItem c) async {
    try {
      String customer = 'عميل نقدي';
      String invNumber = '';
      DateTime date = c.createdAt;
      if (c.salesInvoiceId != null) {
        final inv = await ref
            .read(salesDetailProvider(c.salesInvoiceId!).future);
        if (inv != null) {
          customer = inv.customerName ?? customer;
          invNumber = inv.number;
          date = inv.createdAt;
        }
      }
      if (!context.mounted) return;
      await shareInvoicePdf(
        context,
        InvoicePdfData(
          title: 'طلب تصنيع ${c.code}',
          number:
              invNumber.isEmpty ? c.code : invNumber,
          date: date,
          partnerLabel: 'العميل',
          partnerName: customer,
          statusAr: czStatusAr(c.status),
          rows: [
            InvoicePdfRow(
              name: c.name,
              qty: c.quantity,
              price: c.unitPrice,
              total: c.totalPrice,
            ),
          ],
          subtotal: c.totalPrice,
          discount: 0,
          taxAmount: 0,
          total: c.totalPrice,
          notes: [
            if (c.specSummary.isNotEmpty)
              c.specSummary,
            if (c.createdByName != null)
              'أنشأ الطلب: ${c.createdByName}',
          ].join('\n'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تعذر تجهيز ملف الـ PDF.')));
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
                        .read(manufacturingRepositoryProvider)
                        .rejectCustomized(
                            id, ctrl.text.trim()));
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
  }
}

/// كارت الفاتورة المصدر (ناتج عن فاتورة مبيعات).
class _InvoiceSourceCard extends ConsumerWidget {
  final String invoiceId;
  const _InvoiceSourceCard({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(salesDetailProvider(invoiceId));
    return inv.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (v) {
        if (v == null) return const SizedBox.shrink();
        return AppCard(
          onTap: () =>
              context.push('/sales/${v.id}'),
          padding:
              const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(
                  Icons.point_of_sale_outlined,
                  size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text('ناتج عن فاتورة مبيعات',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey)),
                    Text(
                      '${v.number} • ${v.customerName ?? 'عميل نقدي'}',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_outlined,
                  size: 20),
            ],
          ),
        );
      },
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold),
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
