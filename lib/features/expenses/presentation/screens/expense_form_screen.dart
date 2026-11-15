import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/validators.dart';
import '../../../sales/data/sales_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/expenses_repository.dart';
import '../providers/expenses_providers.dart';

final _dfmt = DateFormat('yyyy/MM/dd');

/// إنشاء مصروف (مسودة).
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() =>
      _ExpenseFormScreenState();
}

class _ExpenseFormScreenState
    extends ConsumerState<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _party = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _categoryId;
  String? _paymentId;
  String? _warehouseId;
  DateTime _date = DateTime.now();
  List<Warehouse> _warehouses = [];
  List<Map<String, dynamic>> _payMethods = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_preload);
  }

  Future<void> _preload() async {
    try {
      final wh =
          await ref.read(warehousesRepositoryProvider).list(onlyActive: true);
      final pm = await ref.read(salesRepositoryProvider).paymentMethods();
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        _payMethods = pm;
        if (wh.isNotEmpty) _warehouseId = wh.first.id;
        final cash = pm.where((e) => e['code'] == 'CASH').toList();
        if (cash.isNotEmpty) _paymentId = cash.first['id'] as String?;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _party.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _addCategorySheet() async {
    final name = TextEditingController();
    final nameAr = TextEditingController();
    final created = await showModalBottomSheet<dynamic>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تصنيف مصروف جديد',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'الاسم *')),
            const SizedBox(height: 8),
            TextField(
                controller: nameAr,
                decoration: const InputDecoration(
                    labelText: 'الاسم بالعربي')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                try {
                  final c = await ref
                      .read(expensesRepositoryProvider)
                      .createCategory(
                        name: name.text,
                        nameAr: nameAr.text,
                      );
                  ref.invalidate(
                      expenseCategoriesProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop(c);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء التصنيف.')));
                  }
                }
              },
              child: const Text('إنشاء واختيار'),
            ),
          ],
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() => _categoryId = created.id as String);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر تصنيف المصروف.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id =
          await ref.read(expensesRepositoryProvider).create({
        'category_id': _categoryId,
        'title': _title.text.trim(),
        'amount': double.parse(_amount.text.trim()),
        'expense_date':
            DateTime(_date.year, _date.month, _date.day)
                .toIso8601String()
                .substring(0, 10),
        'payment_method_id': _paymentId,
        'party_name': _party.text.trim().isEmpty
            ? null
            : _party.text.trim(),
        'reference_number':
            _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
        'warehouse_id': _warehouseId,
        'notes': _notes.text.trim().isEmpty
            ? null
            : _notes.text.trim(),
      });
      ref.invalidate(expensesPageProvider);
      if (mounted) context.pushReplacement('/expenses/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء الحفظ.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(expenseCategoriesProvider);
    return Scaffold(
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: cats.when(
                    loading: () => const Center(
                        child:
                            CircularProgressIndicator()),
                    error: (e, _) =>
                        Text('تعذر تحميل التصنيفات: $e'),
                    data: (list) =>
                        DropdownButtonFormField<String>(
                      key: ValueKey('expcat-$_categoryId'),
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                          labelText: 'التصنيف *'),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(
                              value: c.id,
                              child: Text(c.display,
                                  overflow: TextOverflow
                                      .ellipsis)),
                      ],
                      validator: (v) => v == null
                          ? 'اختر التصنيف'
                          : null,
                      onChanged: (v) => setState(
                          () => _categoryId = v),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'تصنيف جديد',
                  icon:
                      const Icon(Icons.add_outlined),
                  onPressed: _addCategorySheet,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                    labelText:
                        'البيان * (مثال: فاتورة كهرباء شهر سبتمبر)'),
                validator: Validators.required),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'المبلغ * (جنيه)'),
                      validator: Validators.quantity),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(
                        Icons.date_range_outlined,
                        size: 18),
                    label: Text(
                        'تاريخ المصروف\n${_dfmt.format(_date)}',
                        textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paymentId,
              decoration: const InputDecoration(
                  labelText: 'طريقة الدفع'),
              items: [
                for (final m in _payMethods)
                  DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text((m['name_ar'] ??
                              m['code'])
                          .toString())),
              ],
              onChanged: (v) =>
                  setState(() => _paymentId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _party,
                decoration: const InputDecoration(
                    labelText:
                        'المورد/الجهة (مثال: شركة الكهرباء)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _reference,
                decoration: const InputDecoration(
                    labelText:
                        'رقم المرجع (اختياري)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _warehouseId,
              decoration: const InputDecoration(
                  labelText: 'المخزن/الفرع'),
              items: [
                const DropdownMenuItem(
                    value: null,
                    child: Text('بدون')),
                for (final w in _warehouses)
                  DropdownMenuItem(
                      value: w.id,
                      child: Text(
                          '${w.name} (${w.code})')),
              ],
              onChanged: (v) =>
                  setState(() => _warehouseId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)')),
            const SizedBox(height: 8),
            Text(
              'إرفاق الفاتورة متاح بعد الحفظ من صفحة المصروف.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
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
                  : Text(
                      'حفظ (${AppFormat.money(double.tryParse(_amount.text) ?? 0)})'),
            ),
          ],
        ),
      ),
    );
  }
}
