import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_products.dart' show LocalDataFailure;
import 'local_products_screens.dart' show pickLocalProduct;
import 'local_ui.dart';
import 'local_warehouses.dart';

/// مخازن اللوكال: قايمة + إضافة.
class LocalWarehousesScreen extends ConsumerWidget {
  const LocalWarehousesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مخزن جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم المخزن *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'الكود (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(localWarehousesRepositoryProvider)
          .create(name: name.text, code: code.text);
      ref.invalidate(localWarehousesProvider);
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(localWarehousesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('المخازن')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add_outlined),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر التحميل.')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('لا توجد مخازن — ضف أول مخزن.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = items[i];
              return ListTile(
                leading: const Icon(Icons.warehouse_outlined),
                title: Text(w.name),
                subtitle: Text(w.code.isEmpty ? '—' : w.code),
                trailing: w.isActive
                    ? null
                    : const Text(
                        'موقوف',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LocalWarehouseDetailScreen(warehouse: w),
                    ),
                  );
                  ref.invalidate(localWarehousesProvider);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// تفاصيل مخزن: الأرصدة + تسوية + إيقاف/حذف.
class LocalWarehouseDetailScreen extends ConsumerWidget {
  final LocalWarehouse warehouse;
  const LocalWarehouseDetailScreen({super.key, required this.warehouse});

  /// تسوية: اختيار صنف ثم كمية +/− وملاحظة.
  Future<void> _adjust(BuildContext context, WidgetRef ref) async {
    final product = await pickLocalProduct(context, ref);
    if (product == null || !context.mounted) return;
    final qty = TextEditingController();
    final notes = TextEditingController();
    var isIn = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('تسوية: ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('إدخال +')),
                  ButtonSegment(value: false, label: Text('إخراج −')),
                ],
                selected: {isIn},
                onSelectionChanged: (s) => setS(() => isIn = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qty,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الكمية *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final q = parseNum(qty.text);
    final n = notes.text.trim();
    qty.dispose();
    notes.dispose();
    if (ok != true || q <= 0) return;
    try {
      await ref
          .read(localWarehousesRepositoryProvider)
          .adjust(
            warehouseId: warehouse.id,
            productId: product.id,
            delta: isIn ? q : -q,
            notes: n.isEmpty ? null : n,
          );
      ref.invalidate(localStockProvider);
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    await ref
        .read(localWarehousesRepositoryProvider)
        .setActive(warehouse.id, !warehouse.isActive);
    ref.invalidate(localWarehousesProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmLocalDelete(context, 'حذف المخزن؟', warehouse.name);
    if (!ok) return;
    try {
      await ref.read(localWarehousesRepositoryProvider).remove(warehouse.id);
      ref.invalidate(localWarehousesProvider);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } on LocalDataFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.messageAr)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(localStockProvider(warehouse.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(warehouse.name),
        actions: [
          IconButton(
            tooltip: warehouse.isActive ? 'إيقاف' : 'تفعيل',
            icon: Icon(
              warehouse.isActive
                  ? Icons.pause_outlined
                  : Icons.play_arrow_outlined,
            ),
            onPressed: () => _toggle(context, ref),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _adjust(context, ref),
        icon: const Icon(Icons.tune_outlined),
        label: const Text('تسوية'),
      ),
      body: stock.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('تعذر التحميل.')),
        data: (lines) {
          if (lines.isEmpty) {
            return const Center(
              child: Text('لا توجد أرصدة — تنزل مع أول فاتورة مشتريات معتمدة.'),
            );
          }
          return ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final l = lines[i];
              return ListTile(
                title: Text(l.product.name),
                subtitle: Text(
                  'كلي ${l.quantity} • متاح ${l.available}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                ),
                trailing: Text(
                  '${l.available}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: l.available <= 0 ? Colors.red : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
