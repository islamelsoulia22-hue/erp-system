import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../products/data/products_repository.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';

/// دورة الحجز والنواقص المشتركة بين فورم المبيعات وشاشة تفاصيل الفاتورة:
/// - حساب الناقص (المطلوب > المتاح) من مخزن الفاتورة.
/// - حوار واحد: تقليل للمتاح أو حجز المتاح + طلب توريد تلقائي بالناقص.
/// - طلب التوريد مربوط بالفاتورة ويروح لاعتماد المدير.
/// - سؤال العربون بعد الحفظ (يظهر للمدير في الطلب).

class ShortageLine {
  final String? productId;
  final String name;
  final double qty;
  const ShortageLine({
    required this.productId,
    required this.name,
    required this.qty,
  });
}

class ExceedingLine {
  final ShortageLine line;
  final double available;
  const ExceedingLine(this.line, this.available);

  double get missing => line.qty - available;
}

/// المتاح الحالي لكل صنف في مخزن معين.
/// قارئ المزودات (ref.read) — يعمل مع WidgetRef و ProviderRef.
typedef ReadFn = T Function<T>(ProviderListenable<T> provider);

Future<Map<String, double>> fetchAvailability(
    ReadFn read, String warehouseId) async {
  final stock =
      await read(warehousesRepositoryProvider).stockOf(warehouseId);
  return {for (final s in stock) s.productId: s.available};
}

/// السطور اللي المطلوب فيها أكبر من المتاح.
Future<List<ExceedingLine>> findExceeding(
  ReadFn read,
  String warehouseId,
  List<ShortageLine> lines,
) async {
  try {
    final avail = await fetchAvailability(read, warehouseId);
    final out = <ExceedingLine>[];
    for (final l in lines) {
      if (l.productId == null) continue;
      final a = avail[l.productId] ?? 0;
      if (l.qty > a) out.add(ExceedingLine(l, a));
    }
    return out;
  } catch (_) {
    return [];
  }
}

enum ShortageChoice { cancel, adjust, reserve }

/// حوار الناقص الموحد: يعرض المتاح، والاختيار:
/// تقليل للمتاح أو حجز المتاح + طلب الباقي توريد.
Future<ShortageChoice> showShortageDialog(
  BuildContext context,
  List<ExceedingLine> exceeding,
) async {
  final res = await showDialog<ShortageChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('كمية غير متوفرة'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الأصناف دي المطلوب فيها أكبر من المتاح في المخزن. الخصم لا يتم إلا بعد اعتماد المدير.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: exceeding.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 12),
                itemBuilder: (_, k) {
                  final e = exceeding[k];
                  return Text(
                    '• ${e.line.name}\n  المطلوب: ${e.line.qty} — المتاح: ${e.available} — الناقص: ${e.missing}',
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(ShortageChoice.cancel),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(ShortageChoice.adjust),
          child: const Text('تقليل للمتاح'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(ShortageChoice.reserve),
          child: const Text('حجز المتاح + طلب الباقي'),
        ),
      ],
    ),
  );
  return res ?? ShortageChoice.cancel;
}

/// طلب توريد تلقائي بالناقص (مجمّع حسب المورد)، مربوط بالفاتورة
/// ويتبعت لاعتماد المدير فورا. يرجع عدد الطلبات.
Future<int> autoSupplyRequest(
  ReadFn read, {
  required String invoiceId,
  required String warehouseId,
  required List<ShortageLine> lines,
}) async {
  try {
    final avail = await fetchAvailability(read, warehouseId);
    final ids = [
      for (final l in lines)
        if (l.productId != null) l.productId!
    ];
    if (ids.isEmpty) return 0;
    final products =
        await read(productsRepositoryProvider).getMany(ids);
    final byId = {for (final p in products) p.id: p};
    final bySupplier = <String?, List<Map<String, dynamic>>>{};
    for (final l in lines) {
      final pid = l.productId;
      if (pid == null) continue;
      final missing = l.qty - (avail[pid] ?? 0);
      if (missing <= 0) continue;
      final sup = byId[pid]?.supplierId;
      (bySupplier[sup] ??= [])
          .add({'product_id': pid, 'qty': missing});
    }
    if (bySupplier.isEmpty) return 0;
    final repo = read(procurementRepositoryProvider);
    var count = 0;
    for (final e in bySupplier.entries) {
      final prId = await repo.create(
        supplierId: e.key,
        warehouseId: warehouseId,
        reason:
            'طلب تلقائي من فاتورة مبيعات (حجز المتاح + توريد الناقص)',
        salesInvoiceId: invoiceId,
        items: e.value,
      );
      try {
        await repo.submit(prId);
      } catch (_) {}
      count++;
    }
    return count;
  } catch (_) {
    return 0;
  }
}

/// سؤال العربون بعد الحفظ — يفتح الدفع مربوطا بالفاتورة،
/// وإلا يرجع لتفاصيل الفاتورة.
Future<void> depositPrompt(
    BuildContext context, String invoiceId) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تسجيل عربون؟'),
      content: const Text(
          'لو الزبون دفع جزء مقدم (حجز) سجله دلوقتي — المدير هيشوف المبلغ في الطلب.'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(false),
          child: const Text('تخطي'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(true),
          child: const Text('تسجيل عربون'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (go == true) {
    context.pushReplacement('/payments/new?sales=$invoiceId');
  } else {
    context.pushReplacement('/sales/$invoiceId');
  }
}
