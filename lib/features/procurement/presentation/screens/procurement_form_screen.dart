import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../products/data/products_repository.dart';
import '../../../suppliers/data/suppliers_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/procurement_repository.dart';

class _Need {
  final String productId;
  final String name;
  double qty;
  _Need(
      {required this.productId, required this.name, required this.qty});
}

class ProcurementFormScreen extends ConsumerStatefulWidget {
  const ProcurementFormScreen({super.key});
  @override
  ConsumerState<ProcurementFormScreen> createState() =>
      _ProcurementFormScreenState();
}

class _ProcurementFormScreenState
    extends ConsumerState<ProcurementFormScreen> {
  final _reason = TextEditingController();
  String? _supplierId;
  String? _supplierName;
  String? _warehouseId;
  List<Warehouse> _warehouses = [];
  final _needs = <_Need>[];
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
        if (wh.isNotEmpty) _warehouseId = wh.first.id;
      });
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickSupplier() async {
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختيار مورد (اختياري)',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث'))),
                IconButton(
                  icon: const Icon(Icons.search_outlined),
                  onPressed: () async {
                    results = await ref
                        .read(suppliersRepositoryProvider)
                        .search(query: q.text, pageSize: 20);
                    setS(() {});
                  },
                ),
              ]),
              for (final s in results)
                ListTile(
                  title: Text(s.name as String),
                  onTap: () {
                    setState(() {
                      _supplierId = s.id as String;
                      _supplierName = s.name as String;
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('صنف ناقص (المطلوب > المتاح)',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: q,
                        decoration: const InputDecoration(
                            labelText: 'بحث'))),
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
              for (final p in results)
                ListTile(
                  title: Text((p as dynamic).name as String),
                  trailing: TextButton(
                    child: const Text('اختيار'),
                    onPressed: () {
                      setState(() => _needs.add(_Need(
                          productId: (p as dynamic).id as String,
                          name: (p as dynamic).name as String,
                          qty: 1)));
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_warehouseId == null || _needs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختر المخزن وأضف صنفا واحدا على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id =
          await ref.read(procurementRepositoryProvider).create(
                supplierId: _supplierId,
                warehouseId: _warehouseId!,
                reason: _reason.text,
                items: [
                  for (final n in _needs)
                    {'product_id': n.productId, 'qty': n.qty},
                ],
              );
      ref.invalidate(procurementPageProvider);
      if (mounted) {
        context.pushReplacement('/procurement/$id');
      }
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
            title: Text(_supplierName ?? 'مورد (اختياري)'),
            trailing: TextButton(
                onPressed: _pickSupplier,
                child: const Text('اختيار')),
          ),
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration:
                const InputDecoration(labelText: 'المخزن *'),
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
              controller: _reason,
              decoration: const InputDecoration(
                  labelText:
                      'السبب (مثال: مطلوب 100 متاح 60)')),
          const Divider(height: 24),
          Row(children: [
            const Text('الأصناف المطلوبة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
                onPressed: _pickProduct,
                icon: const Icon(Icons.add_outlined),
                label: const Text('إضافة')),
          ]),
          for (int i = 0; i < _needs.length; i++)
            Card(
              child: ListTile(
                title: Text(_needs[i].name),
                subtitle:
                    Text('المطلوب: ${_needs[i].qty}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon:
                            const Icon(Icons.remove_outlined),
                        onPressed: () => setState(() {
                              _needs[i].qty -= 1;
                              if (_needs[i].qty <= 0) {
                                _needs.removeAt(i);
                              }
                            })),
                    IconButton(
                        icon: const Icon(Icons.add_outlined),
                        onPressed: () => setState(
                            () => _needs[i].qty += 1)),
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
