import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../data/customers_repository.dart';
import '../providers/customers_providers.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormScreen({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormScreen> createState() =>
      _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _company = TextEditingController();
  final _notes = TextEditingController();
  String? _addressId;
  bool _active = true;
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.customerId != null;

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
    final c =
        await ref.read(customerDetailProvider(widget.customerId!).future);
    if (c == null || !mounted) return;
    _name.text = c.name;
    _phone.text = c.phone ?? '';
    _company.text = c.company ?? '';
    _notes.text = c.notes ?? '';
    setState(() {
      _active = c.isActive;
      _loaded = true;
    });
    // العنوان الافتراضي من جدول العناوين.
    try {
      final addrs = await ref
          .read(customersRepositoryProvider)
          .addressesOf(widget.customerId!);
      if (!mounted) return;
      if (addrs.isNotEmpty) {
        final def = addrs.firstWhere((a) => a.isDefault,
            orElse: () => addrs.first);
        _address.text = def.addressLine ?? '';
        setState(() => _addressId = def.id);
      }
    } catch (_) {}
  }

  Future<void> _saveAddress(String customerId) async {
    final line = _address.text.trim();
    if (line.isEmpty) return;
    await ref.read(customersRepositoryProvider).upsertAddress({
      if (_addressId != null) 'id': _addressId,
      'customer_id': customerId,
      'address_line': line,
      'is_default': true,
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'company':
            _company.text.trim().isEmpty ? null : _company.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'is_active': _active,
      };
      final repo = ref.read(customersRepositoryProvider);
      final id = isEdit
          ? widget.customerId!
          : (await repo.create(data)).id;
      if (isEdit) {
        await repo.update(widget.customerId!, data);
      }
      await _saveAddress(id);
      ref.invalidate(customersPageProvider);
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
                    const InputDecoration(labelText: 'الاسم *'),
                validator: Validators.required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration:
                    const InputDecoration(labelText: 'رقم الهاتف'),
                validator: (v) =>
                    v != null && v.trim().isNotEmpty
                        ? Validators.phone(v)
                        : null),
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
