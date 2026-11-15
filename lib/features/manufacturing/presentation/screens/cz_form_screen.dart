import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/manufacturing_repository.dart';
import '../providers/manufacturing_providers.dart';

class CustomizedFormScreen extends ConsumerStatefulWidget {
  const CustomizedFormScreen({super.key});
  @override
  ConsumerState<CustomizedFormScreen> createState() =>
      _CustomizedFormScreenState();
}

class _CustomizedFormScreenState
    extends ConsumerState<CustomizedFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _raw = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController(text: '0');
  String? _warehouseId;
  List<Warehouse> _warehouses = [];
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
    _name.dispose();
    _desc.dispose();
    _raw.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(manufacturingRepositoryProvider)
          .createCustomized({
        'name': _name.text.trim(),
        'description': _desc.text.trim().isEmpty
            ? null
            : _desc.text.trim(),
        'raw_material': _raw.text.trim().isEmpty
            ? null
            : _raw.text.trim(),
        'quantity': double.parse(_qty.text),
        'unit_price': double.parse(_price.text),
        'warehouse_id': _warehouseId,
        'status': 'DRAFT',
      });
      ref.invalidate(czPageProvider);
      if (mounted) context.pushReplacement('/customized/$id');
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
            body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
                controller: _name,
                decoration:
                    const InputDecoration(labelText: 'الاسم *'),
                validator: Validators.required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _desc,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'الوصف')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _raw,
                decoration: const InputDecoration(
                    labelText: 'الخامة المطلوبة')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextFormField(
                      controller: _qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'الكمية'),
                      validator: Validators.quantity)),
              const SizedBox(width: 12),
              Expanded(
                  child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'سعر الوحدة'),
                      validator: Validators.required)),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _warehouseId,
              decoration:
                  const InputDecoration(labelText: 'المخزن'),
              items: [
                for (final w in _warehouses)
                  DropdownMenuItem(
                      value: w.id,
                      child: Text('${w.name} (${w.code})')),
              ],
              onChanged: (v) =>
                  setState(() => _warehouseId = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2))
                  : const Text('حفظ كمسودة'),
            ),
          ],
        ),
      ),
    );
  }
}
