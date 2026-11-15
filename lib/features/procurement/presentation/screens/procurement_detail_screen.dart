import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/pdf/supply_pdf.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../sales/data/sales_repository.dart';
import '../../../sales/domain/sales.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/procurement_repository.dart';
import '../../domain/procurement.dart';
import 'procurement_list_screen.dart' show prStatusAr;

/// تفاصيل طلب التوريد — دورة حجز المبيعات:
/// - كارت الفاتورة المرتبطة (رقم/عميل/إجمالي/مدفوع كعربون) + زر فتحها.
/// - لكل صنف: المطلوب + المتاح في كل مخزن.
/// - المدير: تعديل الكميات والمخزن قبل الاستلام.
/// - الاستلام في مخزن يحدده المدير (التوصيل وصل) + الزيادة تنزل المخزن.
/// - PDF للمورد (منتج + كمية فقط) + مشاركة واتساب.
class ProcurementDetailScreen extends ConsumerWidget {
  final String requestId;
  const ProcurementDetailScreen(
      {super.key, required this.requestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(procurementDetailProvider(requestId));
    final items = ref.watch(procurementItemsProvider(requestId));
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
      data: (r) {
        if (r == null) {
          return const Center(child: Text('الطلب غير موجود.'));
        }
        final isMine =
            r.requestedBy != null && r.requestedBy == myId;
        final draft =
            r.status == 'DRAFT' || r.status == 'REJECTED';
        final pending = r.status == 'PENDING_APPROVAL';
        final receivable = r.status == 'APPROVED' ||
            r.status == 'PARTIALLY_RECEIVED';
        final canEdit =
            canApprove && (pending || draft);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(r.number,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
                '${r.supplierName ?? 'بدون مورد'} • ${prStatusAr(r.status)}'),
            if (r.warehouseName != null)
              Text('المخزن: ${r.warehouseName}',
                  style: const TextStyle(color: Colors.grey)),
            if (r.reason != null) Text(r.reason!),
            // الفاتورة المرتبطة (حجز مبيعات + عربون).
            if (r.salesInvoiceId != null) ...[
              const SizedBox(height: 12),
              _LinkedInvoiceCard(
                  invoiceId: r.salesInvoiceId!),
            ],
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                      'الأصناف (مطلوب / متاح / ناقص / مستلم)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                ),
                if (canEdit)
                  TextButton.icon(
                    onPressed: () => _editSheet(
                        context, ref, r.id),
                    icon: const Icon(
                        Icons.edit_outlined, size: 18),
                    label: const Text('تعديل الكميات'),
                  ),
              ],
            ),
            items.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) => Text('تعذر التحميل: $e'),
              data: (rows) => Column(
                children: [
                  for (final it in rows)
                    _ProcItemTile(item: it),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (draft)
              FilledButton(
                onPressed: () => _act(
                    context,
                    ref,
                    () => ref
                        .read(procurementRepositoryProvider)
                        .submit(r.id)),
                child: const Text('إرسال للاعتماد'),
              ),
            if (pending &&
                canApprove &&
                (!isMine || isCompanyManager))
              FilledButton(
                onPressed: () => _act(
                    context,
                    ref,
                    () => ref
                        .read(procurementRepositoryProvider)
                        .approve(r.id)),
                child: const Text('اعتماد'),
              ),
            if (pending &&
                canApprove &&
                (!isMine || isCompanyManager))
              OutlinedButton(
                onPressed: () =>
                    _rejectSheet(context, ref, r.id),
                child: const Text('رفض بسبب'),
              ),
            if (pending && isMine && !isCompanyManager)
              const Text(
                  'طلبك بانتظار الاعتماد — لا يمكنك اعتماده بنفسك.',
                  textAlign: TextAlign.center),
            if (pending && !canApprove)
              const Text(
                  'الطلب قيد المراجعة — الاعتماد للمدير فقط.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            if (receivable)
              FilledButton.tonal(
                onPressed: () =>
                    _receiveSheet(context, ref, r),
                child: const Text(
                    'التوصيل وصل — استلام (يزيد المخزون)'),
              ),
            // بعد الاستلام والطلب مربوط بفاتورة: نفذ اعتماد الفاتورة.
            if ((r.status == 'RECEIVED' ||
                    r.status ==
                        'PARTIALLY_RECEIVED') &&
                r.salesInvoiceId != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context
                    .push('/sales/${r.salesInvoiceId}'),
                icon: const Icon(
                    Icons.point_of_sale_outlined,
                    size: 18),
                label: const Text(
                    'فتح فاتورة المبيعات للاعتماد (حجز المخزون)'),
              ),
            ],
            const SizedBox(height: 8),
            // للمورد: PDF بمنتج + كمية فقط + واتساب.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareSupplierPdf(
                        context, ref, r),
                    icon: const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 18),
                    label:
                        const Text('PDF للمورد'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareWhatsApp(
                        context, ref, r),
                    icon: const Icon(
                        Icons.chat_outlined, size: 18),
                    label:
                        const Text('واتساب للمورد'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ));
  }

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() fn) async {
    try {
      await fn();
      ref
        ..invalidate(procurementDetailProvider(requestId))
        ..invalidate(procurementItemsProvider(requestId))
        ..invalidate(procurementPageProvider);
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
                        .read(procurementRepositoryProvider)
                        .reject(id, ctrl.text.trim()));
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
  }

  /// تعديل المدير: كمية كل صنف + المخزن المستلم.
  void _editSheet(
      BuildContext context, WidgetRef ref, String id) {
    final ctrls = <String, TextEditingController>{};
    String? warehouseId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder(
        future: Future.wait([
          ref.read(procurementRepositoryProvider).itemsOf(id),
          ref
              .read(warehousesRepositoryProvider)
              .list(onlyActive: true),
          ref
              .read(procurementRepositoryProvider)
              .getById(id),
        ]),
        builder: (ctx, snap) {
          final rows = snap.hasData
              ? (snap.data![0] as List<ProcurementItem>)
              : const <ProcurementItem>[];
          final whs = snap.hasData
              ? (snap.data![1] as List<Warehouse>)
              : const <Warehouse>[];
          final req = snap.hasData
              ? (snap.data![2] as ProcurementRequest?)
              : null;
          for (final r in rows) {
            ctrls.putIfAbsent(
                r.id,
                () => TextEditingController(
                    text: r.requested.toString()));
          }
          warehouseId ??= req?.warehouseId;
          return StatefulBuilder(
            builder: (ctx, setS) => Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx)
                          .viewInsets
                          .bottom +
                      16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text('تعديل الكميات والمخزن',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'زود الكمية لو عايز تجيب زيادة مع طلب الفاتورة — الزيادة تنزل المخزن.',
                    style: TextStyle(
                        color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: warehouseId,
                    decoration: const InputDecoration(
                        labelText:
                            'المخزن المستلم (تنزل فيه الزيادة)'),
                    items: [
                      for (final w in whs)
                        DropdownMenuItem(
                            value: w.id,
                            child: Text(
                                '${w.name} (${w.code})')),
                    ],
                    onChanged: (v) =>
                        setS(() => warehouseId = v),
                  ),
                  const SizedBox(height: 8),
                  for (final r in rows)
                    TextField(
                      controller: ctrls[r.id],
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                          labelText:
                              '${r.productName ?? 'صنف'} (مستلم ${r.received})'),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: snap.hasData
                        ? () async {
                            final lines =
                                <Map<String, dynamic>>[];
                            for (final r in rows) {
                              final q = double.tryParse(
                                      ctrls[r.id]!
                                          .text
                                          .trim()) ??
                                  -1;
                              if (q <= 0) {
                                ScaffoldMessenger.of(
                                        ctx)
                                    .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'كل الكميات يجب أن تكون أكبر من صفر.')));
                                return;
                              }
                              lines.add({
                                'item_id': r.id,
                                'qty': q,
                              });
                            }
                            try {
                              await ref
                                  .read(
                                      procurementRepositoryProvider)
                                  .adjust(id,
                                      warehouseId:
                                          warehouseId,
                                      items: lines);
                              ref
                                ..invalidate(
                                    procurementDetailProvider(
                                        id))
                                ..invalidate(
                                    procurementItemsProvider(
                                        id))
                                ..invalidate(
                                    procurementPageProvider);
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(
                                        context)
                                    .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'تم تعديل الطلب.')));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(
                                        ctx)
                                    .showSnackBar(SnackBar(
                                        content: Text(e
                                                is AppFailure
                                            ? e.messageAr
                                            : 'تعذر التعديل.')));
                              }
                            }
                          }
                        : null,
                    child: const Text('حفظ التعديل'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// استلام مع اختيار المخزن (التوصيل وصل — تنفيذ).
  void _receiveSheet(BuildContext context, WidgetRef ref,
      ProcurementRequest r) {
    final ctrls = <String, TextEditingController>{};
    String? warehouseId = r.warehouseId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder(
        future: Future.wait([
          ref.read(procurementRepositoryProvider).itemsOf(r.id),
          ref
              .read(warehousesRepositoryProvider)
              .list(onlyActive: true),
        ]),
        builder: (ctx, snap) {
          final rows = snap.hasData
              ? (snap.data![0] as List<ProcurementItem>)
              : const <ProcurementItem>[];
          final whs = snap.hasData
              ? (snap.data![1] as List<Warehouse>)
              : const <Warehouse>[];
          for (final row in rows) {
            ctrls.putIfAbsent(
                row.id, () => TextEditingController());
          }
          return StatefulBuilder(
            builder: (ctx, setS) => Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx)
                          .viewInsets
                          .bottom +
                      16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  const Text('التوصيل وصل — الكميات المستلمة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: warehouseId,
                    decoration: const InputDecoration(
                        labelText:
                            'المخزن المستلم * (تنزل فيه الكمية)'),
                    items: [
                      for (final w in whs)
                        DropdownMenuItem(
                            value: w.id,
                            child: Text(
                                '${w.name} (${w.code})')),
                    ],
                    onChanged: (v) =>
                        setS(() => warehouseId = v),
                  ),
                  const SizedBox(height: 8),
                  for (final row in rows)
                    TextField(
                      controller: ctrls[row.id],
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                          labelText:
                              '${row.productName} (متبقي ${row.remaining})'),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: snap.hasData
                        ? () async {
                            final lines =
                                <Map<String, dynamic>>[];
                            for (final row in rows) {
                              final q = double.tryParse(
                                      ctrls[row.id]!
                                          .text
                                          .trim()) ??
                                  0;
                              if (q > 0) {
                                lines.add({
                                  'item_id': row.id,
                                  'qty': q,
                                });
                              }
                            }
                            if (lines.isEmpty ||
                                warehouseId == null) {
                              return;
                            }
                            try {
                              await ref
                                  .read(
                                      procurementRepositoryProvider)
                                  .receive(r.id, lines,
                                      null,
                                      warehouseId:
                                          warehouseId);
                              ref
                                ..invalidate(
                                    procurementDetailProvider(
                                        r.id))
                                ..invalidate(
                                    procurementItemsProvider(
                                        r.id))
                                ..invalidate(
                                    procurementPageProvider);
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(
                                        context)
                                    .showSnackBar(const SnackBar(
                                        content: Text(
                                            'تم الاستلام ونزل المخزن المحدد.')));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(
                                        ctx)
                                    .showSnackBar(SnackBar(
                                        content: Text(e
                                                is AppFailure
                                            ? e.messageAr
                                            : 'حدث خطأ — تحقق من الكميات.')));
                              }
                            }
                          }
                        : null,
                    child:
                        const Text('تأكيد الاستلام والتنفيذ'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _shareSupplierPdf(BuildContext context,
      WidgetRef ref, ProcurementRequest r) async {
    try {
      final items = await ref
          .read(procurementRepositoryProvider)
          .itemsOf(r.id);
      if (!context.mounted) return;
      await shareSupplyOrderPdf(
        context,
        SupplyPdfData(
          number: r.number,
          date: r.createdAt,
          supplierName: r.supplierName,
          warehouseName: r.warehouseName,
          rows: [
            for (final it in items)
              SupplyPdfRow(
                name: it.productName ?? 'صنف',
                qty: it.requested,
              ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'تعذر تجهيز الـ PDF.')));
      }
    }
  }

  /// واتساب للمورد: يفتح شات برقم المورد ونص الطلب (منتج + كمية).
  Future<void> _shareWhatsApp(BuildContext context,
      WidgetRef ref, ProcurementRequest r) async {
    try {
      final phone = await ref
          .read(procurementRepositoryProvider)
          .supplierPhone(r.supplierId);
      final items = await ref
          .read(procurementRepositoryProvider)
          .itemsOf(r.id);
      final buf = StringBuffer()
        ..writeln('طلب توريد ${r.number}')
        ..writeln('المطلوب:');
      for (final it in items) {
        buf.writeln(
            '- ${it.productName ?? 'صنف'}: ${it.requested}');
      }
      final text = buf.toString();
      if (phone == null) {
        // بدون رقم: شيت المشاركة (يختار واتساب يدويا) + نص جاهز.
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'لا يوجد رقم للمورد — هتتفتح المشاركة العامة.')));
        await shareSupplyOrderPdf(
          context,
          SupplyPdfData(
            number: r.number,
            date: r.createdAt,
            supplierName: r.supplierName,
            warehouseName: r.warehouseName,
            rows: [
              for (final it in items)
                SupplyPdfRow(
                  name: it.productName ?? 'صنف',
                  qty: it.requested,
                ),
            ],
          ),
        );
        return;
      }
      final uri = Uri.parse(
          'https://wa.me/${normalizeWhatsPhone(phone)}?text=${Uri.encodeComponent(text)}');
      final ok = await launchUrl(uri,
          mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('تعذر فتح واتساب.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is AppFailure
                ? e.messageAr
                : 'تعذر المشاركة.')));
      }
    }
  }
}

/// كارت الفاتورة المرتبطة: رقم/عميل/إجمالي/مدفوع (حجز) + فتحها للاعتماد.
class _LinkedInvoiceCard extends ConsumerWidget {
  final String invoiceId;
  const _LinkedInvoiceCard({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(_linkedInvoiceProvider(invoiceId));
    final paid = ref.watch(_invoicePaidProvider(invoiceId));
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: inv.when(
          loading: () => const Center(
              child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2))),
          error: (_, _) =>
              const Text('تعذر تحميل الفاتورة المرتبطة.'),
          data: (s) {
            if (s == null) {
              return const Text('الفاتورة المرتبطة غير موجودة.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                        Icons.point_of_sale_outlined,
                        size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'فاتورة مبيعات ${s.number} — ${s.customerName}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context
                          .push('/sales/${s.id}'),
                      child: const Text('فتح'),
                    ),
                  ],
                ),
                Text(
                    'الإجمالي: ${AppFormat.money(s.grandTotal)} • الحالة: ${_statusAr(s.status)}'),
                paid.when(
                  loading: () => const Text(
                      'المدفوع: …',
                      style: TextStyle(fontSize: 12)),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (v) => Text(
                    v > 0
                        ? 'حجز — مدفوع مقدم: ${AppFormat.money(v)}'
                        : 'لا يوجد مدفوع مقدم على الفاتورة.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: v > 0
                            ? Colors.green.shade800
                            : Colors.grey),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            );
          },
        ),
      ),
    );
  }

  String _statusAr(String s) => switch (s) {
        'DRAFT' => 'مسودة',
        'PENDING_APPROVAL' => 'بانتظار الاعتماد',
        'APPROVED' => 'معتمدة (محجوز)',
        'REJECTED' => 'مرفوضة',
        'CANCELLED' => 'ملغاة',
        _ => s,
      };
}

/// سطر صنف: المطلوب + المتاح في كل مخزن (للمدير قبل الاعتماد).
class _ProcItemTile extends ConsumerWidget {
  final ProcurementItem item;
  const _ProcItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = item.productId == null
        ? null
        : ref.watch(_productStockProvider(item.productId!));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName ?? 'صنف',
                style: const TextStyle(
                    fontWeight: FontWeight.bold)),
            Text(
                'مطلوب ${item.requested} • متاح ${item.available} • ناقص ${item.missing} • مستلم ${item.received}'),
            if (stock != null)
              stock.when(
                loading: () => const Text(
                    'مخزون المخازن: …',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey)),
                error: (_, _) => const SizedBox.shrink(),
                data: (lines) {
                  if (lines.isEmpty) {
                    return const Text(
                      'لا يوجد رصيد في أي مخزن.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey),
                    );
                  }
                  return Text(
                    'في المخازن: ${lines.map((l) => '${l.warehouseName}: ${l.available}').join(' • ')}',
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

final _linkedInvoiceProvider = FutureProvider.autoDispose
    .family<SalesInvoice?, String>((ref, id) {
  return ref.watch(salesRepositoryProvider).getById(id);
});

final _invoicePaidProvider =
    FutureProvider.autoDispose.family<double, String>((ref, id) {
  return ref.watch(procurementRepositoryProvider).invoicePaid(id);
});

final _productStockProvider = FutureProvider.autoDispose
    .family<List<StockLine>, String>((ref, id) {
  return ref.watch(warehousesRepositoryProvider).stockOfProduct(id);
});
