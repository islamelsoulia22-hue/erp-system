import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../products/presentation/providers/products_providers.dart';
import '../../data/suppliers_repository.dart';
import '../providers/suppliers_providers.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final String? supplierId;
  const SupplierFormScreen({super.key, this.supplierId});

  @override
  ConsumerState<SupplierFormScreen> createState() =>
      _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _company = TextEditingController();
  final _notes = TextEditingController();
  String? _supplyCategoryId;
  bool _active = true;
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.supplierId != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _company.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    if (!isEdit || _loaded) return;
    final s =
        await ref.read(supplierDetailProvider(widget.supplierId!).future);
    if (s == null || !mounted) return;
    _name.text = s.name;
    _phone.text = s.phone ?? '';
    _address.text = s.address ?? '';
    _company.text = s.company ?? '';
    _notes.text = s.notes ?? '';
    setState(() {
      _supplyCategoryId = s.supplyCategoryId;
      _active = s.isActive;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address':
            _address.text.trim().isEmpty ? null : _address.text.trim(),
        'company':
            _company.text.trim().isEmpty ? null : _company.text.trim(),
        'supply_category_id': _supplyCategoryId,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'is_active': _active,
      };
      final repo = ref.read(suppliersRepositoryProvider);
      if (isEdit) {
        await repo.update(widget.supplierId!, data);
      } else {
        await repo.create(data);
      }
      ref.invalidate(suppliersPageProvider);
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
    final cats = ref.watch(productCategoriesProvider);
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
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration:
                    const InputDecoration(labelText: 'رقم الهاتف')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'العنوان (اختياري)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _company,
                decoration: const InputDecoration(
                    labelText: 'الشركة التابع لها (اختياري)')),
            const SizedBox(height: 12),
            cats.when(
              loading: () => const Center(
                  child: CircularProgressIndicator()),
              error: (e, _) =>
                  Text('تعذر تحميل الفئات: $e'),
              data: (list) =>
                  DropdownButtonFormField<String>(
                initialValue: _supplyCategoryId,
                decoration: const InputDecoration(
                    labelText:
                        'بيوردلك إيه؟ (الفئة — اختياري)'),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('بدون تحديد')),
                  for (final c in list)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text(c.display)),
                ],
                onChanged: (v) => setState(
                    () => _supplyCategoryId = v),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)')),
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
