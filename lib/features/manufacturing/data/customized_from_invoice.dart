import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../products/data/products_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../presentation/providers/manufacturing_providers.dart';
import 'manufacturing_repository.dart';

/// بعد إرسال فاتورة مبيعات للاعتماد: كل سطر صنف خاص (CUSTOMIZED)
/// بدون طلب مرتبط → ينشئ طلب تصنيع (customized_item) ويرسله
/// للاعتماد تلقائيا، ويربطه بالسطر، ويشعر المعتمدين.
/// الأصناف العادية تكمل مسار المخزون الطبيعي بدون أي تغيير.
/// يرجع عدد طلبات التصنيع المنشأة. لا يرمي أخطاء أبدا.
Future<int> ensureCustomizedForInvoice(
    WidgetRef ref, String invoiceId) async {
  try {
    final salesRepo = ref.read(salesRepositoryProvider);
    final mfgRepo =
        ref.read(manufacturingRepositoryProvider);
    final inv = await salesRepo.getById(invoiceId);
    if (inv == null) return 0;
    final items = await salesRepo.itemsOf(invoiceId);
    final custom =
        items.where((it) => it.isCustom).toList();
    if (custom.isEmpty) return 0;
    final creatorName = ref
        .read(myProfileProvider)
        .value?['full_name'] as String?;
    var count = 0;
    for (final it in custom) {
      if (it.customizedItemId != null) continue;
      try {
        final czId = await mfgRepo.createCustomized({
          'name': it.itemName,
          'description': it.customNotes,
          'raw_material': it.rawMaterialName,
          'raw_material_id': it.rawMaterialId,
          'length': it.lengthValue,
          'length_unit': it.lengthUnit,
          'width': it.widthValue,
          'width_unit': it.widthUnit,
          'qty_per_roll': it.qtyPerRoll,
          'unit': it.customUnit,
          'quantity': it.quantity,
          'unit_price': it.unitPrice,
          'warehouse_id': inv.warehouseId,
          'sales_invoice_id': invoiceId,
          'sales_invoice_item_id': it.id,
          'created_by_name': creatorName,
        });
        await mfgRepo.submitCustomized(czId);
        await salesRepo.setCustomizedItem(it.id, czId);
        count++;
        // إشعار المعتمدين بطلب التصنيع الجديد.
        try {
          await ref.read(supabaseClientProvider).rpc(
            'notify_by_permission',
            params: {
              'p_permission': 'sales.approve',
              'p_type': 'APPROVAL',
              'p_title': 'طلب تصنيع جديد يحتاج اعتماد',
              'p_message':
                  '${it.itemName} — فاتورة ${inv.number}',
              'p_entity_type': 'CUSTOMIZED_ITEM',
              'p_entity_id': czId,
            },
          );
        } catch (_) {}
      } catch (e) {
        debugPrint(
            'ensureCustomizedForInvoice item ${it.id} error: $e');
      }
    }
    return count;
  } catch (e) {
    debugPrint('ensureCustomizedForInvoice error: $e');
    return 0;
  }
}

/// اعتماد طلب تصنيع + إنشاء أمر التصنيع تلقائيا ليتسلمه التصنيع.
/// الخامة مكتوبة كتابة — لو طابقت صنفا في المخزون بنفس الاسم
/// بتتربط تلقائيا كخامة للأمر، ولو لا يعتمد الطلب فقط
/// ومسؤول التصنيع ينشئ الأمر يدويا بخاماته.
/// يرجع رسالة توضيحية (null = كله تمام).
/// لا يرمي لو الاعتماد نفسه نجح — الفشل في الأمر فقط يوصف.
Future<String?> approveCustomizedAndMakeOrder(
    WidgetRef ref, String czId) async {
  final mfg = ref.read(manufacturingRepositoryProvider);
  await mfg.approveCustomized(czId);
  try {
    final cz = await mfg.getCustomized(czId);
    if (cz == null) return 'تم الاعتماد.';
    if (cz.warehouseId == null) {
      return 'تم الاعتماد بدون أمر تصنيع (لا يوجد مخزن).';
    }
    // حل الخامة: مربوطة مباشرة أو مطابقة الاسم بالمخزون.
    String? materialId = cz.rawMaterialId;
    materialId ??= await _resolveMaterialId(
        ref, cz.rawMaterial);
    if (materialId == null) {
      return 'تم الاعتماد — أنشئ أمر التصنيع يدويا وحدد خاماته (الخامة "${cz.rawMaterial ?? '—'}" غير مربوطة بالمخزون).';
    }
    final perUnit =
        (cz.qtyPerRoll != null && cz.qtyPerRoll! > 0)
            ? cz.qtyPerRoll!
            : 1;
    await mfg.createOrder(
      customizedId: cz.id,
      warehouseId: cz.warehouseId,
      quantity: cz.quantity,
      materials: [
        {
          'product_id': materialId,
          'qty': cz.quantity * perUnit,
        },
      ],
    );
    ref.invalidate(moPageProvider);
    return null;
  } catch (e) {
    debugPrint('approveCustomizedAndMakeOrder MO error: $e');
    return 'تم الاعتماد، وتعذر إنشاء أمر التصنيع تلقائيا.';
  }
}

/// مطابقة اسم الخامة المكتوبة بصنف في المخزون (تطابق تام).
/// ترجع id الصنف أو null. صامتة الفشل.
Future<String?> _resolveMaterialId(
    WidgetRef ref, String? typedName) async {
  try {
    final name = typedName?.trim();
    if (name == null || name.isEmpty) return null;
    final results = await ref
        .read(productsRepositoryProvider)
        .search(query: name, pageSize: 10);
    final want = name.toLowerCase();
    for (final p in results) {
      if (p.name.trim().toLowerCase() == want) return p.id;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// إشعار فريق المبيعات (لاستدعائه عند جاهزية التصنيع مثلا).
/// صامت الفشل — الإشعار مساعد فقط.
Future<void> notifySalesTeam(
  WidgetRef ref, {
  required String title,
  String? message,
  String? entityType,
  String? entityId,
}) async {
  try {
    await ref.read(supabaseClientProvider).rpc(
      'notify_by_permission',
      params: {
        'p_permission': 'sales.create',
        'p_type': 'INFO',
        'p_title': title,
        'p_message': message,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
      },
    );
  } catch (e) {
    debugPrint('notifySalesTeam error: $e');
  }
}
