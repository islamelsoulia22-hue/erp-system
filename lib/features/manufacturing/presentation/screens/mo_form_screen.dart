import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../products/data/products_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/manufacturing_repository.dart';
import '../providers/manufacturing_providers.dart';

class _Mat {
  final String productId;
  final String name;
  double qty;
  _Mat({required this.productId, required this.name, required this.qty});
}

class ManufacturingOrderFormScreen extends ConsumerStatefulWidget {
  final String? customizedId;
  const ManufacturingOrderFormScreen({super.key, this.customizedId});

  @override
  ConsumerState<ManufacturingOrderFormScreen> createState() =>
      _ManufacturingOrderFormScreenState();
}

class _ManufacturingOrderFormScreenState
    extends ConsumerState<ManufacturingOrderFormScreen> {
  String? _warehouseId;
  String? _finishedId;
  String? _finishedName;
  final _finishedQty = TextEditingController(text: '1');
  List<Warehouse> _warehouses = [];
  final _mats = <_Mat>[];
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
    _finishedQty.dispose();
    super.dispose();
  }

  Future<void> _pickMaterial() async {
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
              const Text('خامة من المخزون',
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
                      setState(() => _mats.add(_Mat(
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

  Future<void> _pickFinished() async {
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
              const Text('المنتج التام (يضاف للمخزون عند الإتمام)',
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
                  onTap: () {
                    setState(() {
                      _finishedId = (p as dynamic).id as String;
                      _finishedName =
                          (p as dynamic).name as String;
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

  Future<void> _save() async {
    if (_warehouseId == null || _mats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختر المخزن وأضف خامة واحدة على الأقل.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(manufacturingRepositoryProvider)
          .createOrder(
            customizedId: widget.customizedId,
            warehouseId: _warehouseId,
            finishedProductId: _finishedId,
            finishedQty: _finishedId == null
                ? null
                : double.tryParse(_finishedQty.text) ?? 1,
            materials: [
              for (final m in _mats)
                {'product_id': m.productId, 'qty': m.qty},
            ],
          );
      ref.invalidate(moPageProvider);
      if (mounted) {
        context.pushReplacement('/manufacturing-orders/$id');
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(_finishedName ?? 'منتج تام (اختياري)'),
            trailing: TextButton(
                onPressed: _pickFinished,
                child: const Text('اختيار')),
          ),
          if (_finishedId != null)
            TextField(
                controller: _finishedQty,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'كمية الإنتاج التام')),
          const Divider(height: 24),
          Row(children: [
            const Text('الخامات المطلوبة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
                onPressed: _pickMaterial,
                icon: const Icon(Icons.add_outlined),
                label: const Text('إضافة خامة')),
          ]),
          for (int i = 0; i < _mats.length; i++)
            Card(
              child: ListTile(
                title: Text(_mats[i].name),
                subtitle:
                    Text('المطلوب: ${_mats[i].qty}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon:
                            const Icon(Icons.remove_outlined),
                        onPressed: () => setState(() {
                              _mats[i].qty -= 1;
                              if (_mats[i].qty <= 0) {
                                _mats.removeAt(i);
                              }
                            })),
                    IconButton(
                        icon: const Icon(Icons.add_outlined),
                        onPressed: () => setState(
                            () => _mats[i].qty += 1)),
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
                : const Text('إنشاء الأمر'),
          ),
        ],
      ),
    );
  }
}
