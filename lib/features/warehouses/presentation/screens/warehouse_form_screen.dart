import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../data/warehouses_repository.dart';
import '../providers/warehouses_providers.dart';

class WarehouseFormScreen extends ConsumerStatefulWidget {
  final String? warehouseId;
  const WarehouseFormScreen({super.key, this.warehouseId});

  @override
  ConsumerState<WarehouseFormScreen> createState() =>
      _WarehouseFormScreenState();
}

class _WarehouseFormScreenState extends ConsumerState<WarehouseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  bool _active = true;
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.warehouseId != null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    if (!isEdit || _loaded) return;
    final w =
        await ref.read(warehouseDetailProvider(widget.warehouseId!).future);
    if (w == null || !mounted) return;
    _name.text = w.name;
    _location.text = w.location ?? '';
    setState(() {
      _active = w.isActive;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'location': _location.text.trim().isEmpty
            ? null
            : _location.text.trim(),
        'is_active': _active,
      };
      final repo = ref.read(warehousesRepositoryProvider);
      if (isEdit) {
        await repo.update(widget.warehouseId!, data);
      } else {
        await repo.create(data);
      }
      ref.invalidate(warehousesListProvider);
      if (mounted) context.pop();
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
    if (isEdit && !_loaded) _prefill();
    return Scaffold(
            body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
                controller: _name,
                decoration:
                    const InputDecoration(labelText: 'اسم المخزن *'),
                validator: Validators.required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _location,
                decoration:
                    const InputDecoration(labelText: 'الموقع')),
            SwitchListTile(
                title: const Text('نشط'),
                value: _active,
                onChanged: (v) => setState(() => _active = v)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'حفظ' : 'إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}
