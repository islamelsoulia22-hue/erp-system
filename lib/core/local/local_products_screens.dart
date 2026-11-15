import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pdf/barcode_pdf.dart';
import '../printing/xprinter_service.dart';
import '../widgets/app_pagination.dart';
import 'local_products.dart';

/// شيت اختيار صنف لوكال (بحث) — للفواتير والتسويات.
/// يرجع الصنف المختار أو null.
Future<LocalProduct?> pickLocalProduct(
  BuildContext context,
  WidgetRef ref,
) async {
  final q = TextEditingController();
  var query = '';
  return showModalBottomSheet<LocalProduct>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اختار الصنف',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: q,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'بحث بالاسم / SKU',
                    ),
                    onSubmitted: (_) => setS(() => query = q.text.trim()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () => setS(() => query = q.text.trim()),
                ),
              ],
            ),
            Flexible(
              child: Consumer(
                builder: (ctx2, ref2, _) {
                  final data = ref2.watch(
                    localProductsPageProvider((query: query, page: 0)),
                  );
                  return data.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                    error: (_, _) => const Text('تعذر البحث.'),
                    data: (paged) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in paged.items.take(8))
                          ListTile(
                            dense: true,
                            title: Text(p.name),
                            subtitle: Text(
                              'بيع ${p.salePrice} • شراء ${p.purchasePrice}',
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                            ),
                            trailing: const Text('اختار'),
                            onTap: () => Navigator.of(ctx).pop(p),
                          ),
                        if (paged.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد نتائج مطابقة'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

double _num(String s) => double.tryParse(s.trim()) ?? 0;

/// قايمة الأصناف اللوكال: بحث + ترقيم + إضافة.
class LocalProductsListScreen extends ConsumerStatefulWidget {
  const LocalProductsListScreen({super.key});

  @override
  ConsumerState<LocalProductsListScreen> createState() =>
      _LocalProductsListScreenState();
}

class _LocalProductsListScreenState
    extends ConsumerState<LocalProductsListScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _doSearch() {
    setState(() {
      _query = _search.text.trim();
      _page = 0;
    });
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LocalProductFormScreen()),
    );
    if (saved == true) {
      ref.invalidate(localProductsPageProvider);
    }
  }

  Future<void> _openDetail(LocalProduct p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LocalProductDetailScreen(product: p)),
    );
    if (changed == true) {
      ref.invalidate(localProductsPageProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(
      localProductsPageProvider((query: _query, page: _page)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف — نسخة الجهاز')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add_outlined),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _doSearch(),
                    decoration: const InputDecoration(
                      labelText: 'بحث بالاسم أو SKU',
                      prefixIcon: Icon(Icons.search_outlined),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _doSearch, child: const Text('بحث')),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  e is LocalDataFailure ? e.messageAr : 'تعذر التحميل.',
                ),
              ),
              data: (paged) {
                if (paged.items.isEmpty) {
                  return const Center(
                    child: Text('لا توجد أصناف — ضف أول صنف.'),
                  );
                }
                return ListView.separated(
                  itemCount: paged.items.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= paged.items.length) {
                      return AppPagination(
                        page: _page,
                        total: paged.total,
                        pageSize: LocalProductsRepository.pageSize,
                        onGo: (p) => setState(() => _page = p),
                      );
                    }
                    final p = paged.items[i];
                    return ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(p.name),
                      subtitle: Text(
                        '${p.sku.isEmpty ? 'بدون SKU' : p.sku}'
                        '${p.primaryBarcode.isEmpty ? '' : ' • ${p.primaryBarcode}'}'
                        ' • شراء ${p.purchasePrice} • بيع ${p.salePrice}',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                      ),
                      trailing: p.isActive
                          ? null
                          : const Text(
                              'موقوف',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                      onTap: () => _openDetail(p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// إضافة صنف لوكال.
class LocalProductFormScreen extends ConsumerStatefulWidget {
  const LocalProductFormScreen({super.key});

  @override
  ConsumerState<LocalProductFormScreen> createState() =>
      _LocalProductFormScreenState();
}

class _LocalProductFormScreenState
    extends ConsumerState<LocalProductFormScreen> {
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _buy = TextEditingController();
  final _sell = TextEditingController();
  final _min = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _buy.dispose();
    _sell.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(localProductsRepositoryProvider)
          .create(
            name: _name.text,
            sku: _sku.text,
            purchasePrice: _num(_buy.text),
            salePrice: _num(_sell.text),
            minimumStock: _num(_min.text),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LocalDataFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.messageAr)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر الحفظ.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صنف جديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'اسم الصنف *',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sku,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'SKU (اختياري)',
              prefixIcon: Icon(Icons.tag_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'سعر الشراء'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _sell,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'سعر البيع'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'الحد الأدنى للمخزون'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ الصنف'),
          ),
        ],
      ),
    );
  }
}

/// تفاصيل صنف لوكال: عرض + إيقاف/تفعيل + حذف.
class LocalProductDetailScreen extends ConsumerWidget {
  final LocalProduct product;
  const LocalProductDetailScreen({super.key, required this.product});

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(localProductsRepositoryProvider)
          .setActive(product.id, !product.isActive);
      if (context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر التعديل.')));
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف؟'),
        content: Text('سيتم حذف "${product.name}" نهائيا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(localProductsRepositoryProvider).remove(product.id);
      if (context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر الحذف.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final barcodeAsync = ref.watch(
      localPrimaryBarcodeProvider(product.id),
    );
    final barcode =
        barcodeAsync.maybeWhen(data: (b) => b, orElse: () => null) ??
        product.primaryBarcode;
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('الاسم'),
                  subtitle: Text(product.name),
                ),
                ListTile(
                  title: const Text('SKU'),
                  subtitle: Text(
                    product.sku.isEmpty ? '—' : product.sku,
                    textDirection: TextDirection.ltr,
                  ),
                ),
                ListTile(
                  title: const Text('الباركود'),
                  subtitle: Text(
                    barcode.isEmpty ? 'بدون باركود' : barcode,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _editBarcode(context, ref, barcode),
                ),
                ListTile(
                  title: const Text('سعر الشراء'),
                  subtitle: Text(
                    '${product.purchasePrice}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
                ListTile(
                  title: const Text('سعر البيع'),
                  subtitle: Text(
                    '${product.salePrice}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
                ListTile(
                  title: const Text('الحد الأدنى للمخزون'),
                  subtitle: Text(
                    '${product.minimumStock}',
                    textDirection: TextDirection.ltr,
                  ),
                ),
                ListTile(
                  title: const Text('الحالة'),
                  subtitle: Text(product.isActive ? 'نشط' : 'موقوف'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (barcode.isNotEmpty)
            FilledButton.icon(
              onPressed: () => _printXPrinter(context, ref, barcode),
              icon: const Icon(Icons.label_outlined, size: 18),
              label: const Text('طباعة الباركود XPrinter'),
            ),
          if (barcode.isNotEmpty) const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _editBarcode(context, ref, barcode),
            icon: const Icon(Icons.barcode_reader),
            label: Text(
              barcode.isEmpty ? 'إضافة باركود' : 'تعديل الباركود',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _toggle(context, ref),
            icon: Icon(
              product.isActive
                  ? Icons.pause_outlined
                  : Icons.play_arrow_outlined,
            ),
            label: Text(product.isActive ? 'إيقاف' : 'تفعيل'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _remove(context, ref),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('حذف الصنف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// تعديل الباركود الأساسي من نفس الشاشة.
  Future<void> _editBarcode(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final ctrl = TextEditingController(text: current);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'باركود: ${product.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'رقم الباركود',
                prefixIcon: Icon(Icons.barcode_reader),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(localProductsRepositoryProvider)
                      .setBarcode(
                        productId: product.id,
                        barcode: ctrl.text,
                      );
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } on LocalDataFailure catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.messageAr)),
                    );
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تعذر الحفظ.')),
                    );
                  }
                }
              },
              child: const Text('حفظ الباركود'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      ref.invalidate(localPrimaryBarcodeProvider(product.id));
      ref.invalidate(localProductsPageProvider);
    }
  }

  /// طباعة ملصق الباركود على XPrinter (USB مباشر على اللينكس).
  Future<void> _printXPrinter(
    BuildContext context,
    WidgetRef ref,
    String barcode,
  ) async {
    final code = barcode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف باركود أولا.')),
      );
      return;
    }
    await showXPrinterSheet(
      context,
      [
        BarcodeLabelData(
          productId: product.id,
          productName: product.name,
          barcode: code,
        ),
      ],
    );
  }
}
