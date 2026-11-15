import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../suppliers/data/suppliers_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/purchases_repository.dart';
import '../../domain/purchases.dart';
import '../providers/purchases_providers.dart';

class _Line {
  final String? productId;
  final String name;
  final String? sku;
  double qty;
  double cost;
  double taxRate = 14;
  _Line(
      {this.productId,
      required this.name,
      this.sku,
      required this.qty,
      required this.cost});
}

/// Shared product picker used by order + invoice forms.
Future<Product?> pickProduct(
    BuildContext context, WidgetRef ref) async {
  final q = TextEditingController();
  List<Product> results = [];
  Product? picked;
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('بحث منتج',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: q,
                      decoration: const InputDecoration(
                          labelText: 'اسم / SKU / باركود'))),
              IconButton(
                icon: const Icon(Icons.search_outlined),
                onPressed: () async {
                  try {
                    results = await ref
                        .read(productsRepositoryProvider)
                        .search(query: q.text, pageSize: 20);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'حدث خطأ أثناء البحث.')),
                      );
                    }
                    return;
                  }
                  setS(() {});
                },
              ),
            ]),
            for (final p in results)
              ListTile(
                title: Text(p.name),
                subtitle: Text(p.sku,
                    textDirection: TextDirection.ltr),
                trailing: TextButton(
                  child: const Text('اختيار'),
                  onPressed: () {
                    picked = p;
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
  return picked;
}

Future<Map<String, String>?> pickSupplier(
    BuildContext context, WidgetRef ref) async {
  final q = TextEditingController();
  List<dynamic> results = [];
  Map<String, String>? picked;
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختيار مورد',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: q,
                      decoration: const InputDecoration(
                          labelText: 'بحث'))),
              IconButton(
                icon: const Icon(Icons.search_outlined),
                onPressed: () async {
                  try {
                    results = await ref
                        .read(suppliersRepositoryProvider)
                        .search(query: q.text, pageSize: 20);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'حدث خطأ أثناء البحث.')),
                      );
                    }
                    return;
                  }
                  setS(() {});
                },
              ),
            ]),
            for (final s in results)
              ListTile(
                title: Text(s.name as String),
                subtitle: Text(s.code as String),
                onTap: () {
                  picked = {
                    'id': s.id as String,
                    'name': s.name as String
                  };
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
  return picked;
}

class PurchaseOrderFormScreen extends ConsumerStatefulWidget {
  const PurchaseOrderFormScreen({super.key});
  @override
  ConsumerState<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState
    extends ConsumerState<PurchaseOrderFormScreen> {
  final _ref = TextEditingController();
  String? _supplierId;
  String? _supplierName;
  String? _warehouseId;
  List<Warehouse> _warehouses = [];
  final _lines = <_Line>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final wh = await ref
          .read(warehousesRepositoryProvider)
          .list(onlyActive: true);
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        // المخزن إجباري باختيار صريح من المستخدم — مفيش
        // اختيار تلقائي عشان الكمية متنزلش في مخزن غلط.
      });
    });
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(context, ref);
    if (p == null) return;
    setState(() => _lines.add(_Line(
        productId: p.id,
        name: p.name,
        sku: p.sku,
        qty: 1,
        cost: p.purchasePrice)));
  }

  Future<void> _save() async {
    if (_supplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختار المورد أولا.')));
      return;
    }
    if (_warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختار المخزن اللي هتنزل فيه الكمية أولا.')));
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أضف صنفا واحدا على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(purchasesRepositoryProvider).createOrder(
            supplierId: _supplierId,
            warehouseId: _warehouseId,
            reference: _ref.text,
            items: [
              for (final l in _lines)
                POItemInput(
                    productId: l.productId,
                    productName: l.name,
                    sku: l.sku,
                    quantity: l.qty,
                    unitCost: l.cost,
                    taxRate: l.taxRate),
            ],
          );
      ref.invalidate(poPageProvider);
      if (mounted) context.pushReplacement('/purchase-orders/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء تنفيذ العملية.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
            body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(_supplierName ?? 'اختيار المورد *'),
            trailing: TextButton(
              child: const Text('اختيار'),
              onPressed: () async {
                final s = await pickSupplier(context, ref);
                if (s != null) {
                  setState(() {
                    _supplierId = s['id'];
                    _supplierName = s['name'];
                  });
                }
              },
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration: const InputDecoration(
              labelText: 'المخزن *',
              helperText:
                  'الكمية هتنزل في المخزن اللي تختاره',
            ),
            hint: const Text(
                'اختار المخزن اللي هتنزل فيه الكمية'),
            items: [
              for (final w in _warehouses)
                DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.name} (${w.code})')),
            ],
            onChanged: (v) =>
                setState(() => _warehouseId = v),
          ),
          TextField(
              controller: _ref,
              decoration: const InputDecoration(
                  labelText: 'رقم مرجعي (اختياري)')),
          const Divider(height: 24),
          Row(children: [
            const Text('الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add_outlined),
                label: const Text('إضافة صنف')),
          ]),
          for (int i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(_lines[i].name),
                      subtitle: Text(
                          '${_lines[i].qty} × ${_lines[i].cost}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(
                                  Icons.remove_outlined),
                              onPressed: () => setState(() {
                                    _lines[i].qty -= 1;
                                    if (_lines[i].qty <= 0) {
                                      _lines.removeAt(i);
                                    }
                                  })),
                          IconButton(
                              icon: const Icon(
                                  Icons.add_outlined),
                              onPressed: () => setState(
                                  () =>
                                      _lines[i].qty += 1)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        key: ValueKey('po-tax-$i'),
                        initialValue:
                            _lines[i].taxRate.toString(),
                        keyboardType: const TextInputType
                            .numberWithOptions(decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'الضريبة %',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8),
                        ),
                        onChanged: (v) {
                          final d =
                              double.tryParse(v);
                          if (d != null &&
                              d >= 0 &&
                              d <= 100) {
                            // بدون setState عشان الفوكس ميضيعش أثناء الكتابة.
                            _lines[i].taxRate = d;
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ كمسودة'),
          ),
        ],
      ),
    );
  }
}
