import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../products/presentation/providers/products_providers.dart';

/// وحدات المقاس المتاحة للصنف الخاص.
const customDimUnits = ['mm', 'cm', 'm'];

/// مواصفات صنف خاص (من شيت الإضافة) قبل دخوله الفاتورة.
/// الفئة ثابتة: بكر الباركود — والصنف بيروح للتصنيع تلقائيا
/// بعد إرسال الفاتورة للاعتماد، والمدير بيشوفه في الاعتمادات.
class CustomItemSpec {
  final String name;
  final double qty;
  final double price;
  final double purchasePrice;
  final String unit;
  final double length;
  final String lengthUnit;
  final double width;
  final String widthUnit;
  final String rawMaterialName;
  final double qtyPerRoll;
  final String? notes;

  const CustomItemSpec({
    required this.name,
    required this.qty,
    required this.price,
    required this.purchasePrice,
    required this.unit,
    required this.length,
    required this.lengthUnit,
    required this.width,
    required this.widthUnit,
    required this.rawMaterialName,
    required this.qtyPerRoll,
    this.notes,
  });
}

/// شيت "إضافة صنف خاص" من داخل فاتورة المبيعات.
/// يرجع CustomItemSpec أو null لو اتقفل.
Future<CustomItemSpec?> showCustomItemSheet(
    BuildContext context) {
  return showModalBottomSheet<CustomItemSpec>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CustomItemSheet(),
  );
}

class _CustomItemSheet extends ConsumerStatefulWidget {
  const _CustomItemSheet();

  @override
  ConsumerState<_CustomItemSheet> createState() =>
      _CustomItemSheetState();
}

class _CustomItemSheetState
    extends ConsumerState<_CustomItemSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _purchase = TextEditingController();
  final _unit = TextEditingController(text: 'رول');
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _qtyPerRoll = TextEditingController();
  final _divisor = TextEditingController(text: '100000');
  final _notes = TextEditingController();
  final _cloneQuery = TextEditingController();
  String _lengthUnit = 'mm';
  String _widthUnit = 'mm';
  // الخامة المختارة من خامات بكر الباركود (إجباري بدل الكتابة).
  String? _materialId;
  // فئة بكر الباركود (للاستنساخ من أصنافها الجاهزة).
  String? _rollCategoryId;
  List<Product> _cloneResults = [];
  bool _cloneSearching = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadRollCategory);
  }

  Future<void> _loadRollCategory() async {
    try {
      final cat = await ref
          .read(productsRepositoryProvider)
          .ensureBarcodeRollCategory();
      if (!mounted) return;
      setState(() => _rollCategoryId = cat?.id);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    _purchase.dispose();
    _unit.dispose();
    _length.dispose();
    _width.dispose();
    _qtyPerRoll.dispose();
    _divisor.dispose();
    _notes.dispose();
    _cloneQuery.dispose();
    super.dispose();
  }

  String? _reqNum(String? v, {bool allowZero = false}) {
    final d = double.tryParse((v ?? '').trim());
    if (d == null) return 'رقم غير صالح';
    if (!allowZero && d <= 0) return 'لازم أكبر من صفر';
    if (d < 0) return 'لازم رقم موجب';
    return null;
  }

  double _toMm(double v, String unit) => switch (unit) {
        'cm' => v * 10,
        'm' => v * 1000,
        _ => v,
      };

  /// السعران المحسوبان من الخامة:
  /// سعر الخامة × (الطول+3) × (العرض+3) × العدد / معامل القسمة (يدوي).
  ({double purchase, double sale}) _computedPrices(
      List<BarcodeMaterial> mats) {
    const none = (purchase: 0.0, sale: 0.0);
    final mat = mats.where((m) => m.id == _materialId).toList();
    if (mat.isEmpty) return none;
    final len = double.tryParse(_length.text.trim()) ?? 0;
    final wid = double.tryParse(_width.text.trim()) ?? 0;
    final perRoll = double.tryParse(_qtyPerRoll.text.trim()) ?? 0;
    final divisor =
        double.tryParse(_divisor.text.trim()) ??
            BarcodeRollPricing.defaultDivisor;
    if (len <= 0 || wid <= 0 || perRoll <= 0 || divisor <= 0) {
      return none;
    }
    final l = _toMm(len, _lengthUnit);
    final w = _toMm(wid, _widthUnit);
    return (
      purchase: BarcodeRollPricing.rollPrice(
          mat.first.purchasePrice, l, w, perRoll, divisor),
      sale: BarcodeRollPricing.rollPrice(
          mat.first.salePrice, l, w, perRoll, divisor),
    );
  }

  Future<void> _searchClone() async {
    final catId = _rollCategoryId;
    if (catId == null) return;
    setState(() => _cloneSearching = true);
    try {
      final res = await ref
          .read(productsRepositoryProvider)
          .search(
              query: _cloneQuery.text, categoryId: catId, pageSize: 10);
      if (mounted) setState(() => _cloneResults = res);
    } catch (_) {
      if (mounted) setState(() => _cloneResults = []);
    } finally {
      if (mounted) setState(() => _cloneSearching = false);
    }
  }

  /// استنساخ صنف بكر جاهز: يملأ الاسم والمقاس والخامة فقط —
  /// السعران يدويان في الصنف الخاص (مش كوبي من الصنف الجاهز).
  void _applyClone(Product p, List<BarcodeMaterial> mats) {
    setState(() {
      _name.text = p.name;
      if (p.labelLengthMm != null && p.labelLengthMm! > 0) {
        _length.text = p.labelLengthMm.toString();
        _lengthUnit = 'mm';
      }
      if (p.labelWidthMm != null && p.labelWidthMm! > 0) {
        _width.text = p.labelWidthMm.toString();
        _widthUnit = 'mm';
      }
      if (p.qtyPerRoll != null && p.qtyPerRoll! > 0) {
        _qtyPerRoll.text = p.qtyPerRoll!.toStringAsFixed(0);
      }
      // طابق الخامة بالاسم (عربي أو إنجليزي).
      final want = (p.barcodeMaterialName ?? '').trim().toLowerCase();
      if (want.isNotEmpty) {
        for (final m in mats) {
          final ar = (m.nameAr ?? '').trim().toLowerCase();
          final en = m.name.trim().toLowerCase();
          if (ar == want || en == want) {
            _materialId = m.id;
            break;
          }
        }
      }
    });
  }

  void _submit(List<BarcodeMaterial> mats) {
    if (!_form.currentState!.validate()) return;
    if (_materialId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختار الخامة من بكر الباركود.')));
      return;
    }
    final mat =
        mats.where((m) => m.id == _materialId).toList();
    if (mat.isEmpty) return;
    Navigator.of(context).pop(CustomItemSpec(
      name: _name.text.trim(),
      qty: double.parse(_qty.text.trim()),
      price: double.parse(_price.text.trim()),
      purchasePrice: double.parse(_purchase.text.trim()),
      unit: _unit.text.trim().isEmpty
          ? 'رول'
          : _unit.text.trim(),
      length: double.parse(_length.text.trim()),
      lengthUnit: _lengthUnit,
      width: double.parse(_width.text.trim()),
      widthUnit: _widthUnit,
      rawMaterialName: (mat.first.nameAr?.isNotEmpty == true
          ? mat.first.nameAr!
          : mat.first.name),
      qtyPerRoll: double.parse(_qtyPerRoll.text.trim()),
      notes: _notes.text.trim().isEmpty
          ? null
          : _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final matsAsync = ref.watch(barcodeMaterialsProvider);
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const Text('إضافة صنف خاص',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'الفئة: بكر الباركود 🏷️ — الصنف هيروح للتصنيع تلقائيا بعد إرسال الفاتورة، والمدير هيشوفه في الاعتمادات.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // استنساخ من صنف بكر جاهز (يملأ البيانات).
              const Text('استنساخ من صنف جاهز (اختياري)',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _cloneQuery,
                        decoration: const InputDecoration(
                            labelText:
                                'ابحث في أصناف بكر الباركود',
                            isDense: true),
                        onSubmitted: (_) =>
                            _searchClone())),
                IconButton(
                  icon: _cloneSearching
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(
                          Icons.search_outlined),
                  onPressed: _searchClone,
                ),
              ]),
              for (final p in _cloneResults)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.sku} • بيع ${p.salePrice}',
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: TextButton(
                    child: const Text('استنساخ'),
                    onPressed: () => matsAsync.maybeWhen(
                      data: (mats) =>
                          _applyClone(p, mats),
                      orElse: () {},
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'اسم الصنف *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'اكتب اسم الصنف'
                        : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qty,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText: 'الكمية *'),
                      validator: (v) => _reqNum(v),
                    ),
                  ),
                  const SizedBox(
                      width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                          labelText:
                              'سعر البيع * (جنيه / ${_unit.text.trim().isEmpty ? 'رول' : _unit.text.trim()})'),
                      validator: (v) =>
                          _reqNum(v, allowZero: true),
                      onChanged: (_) =>
                          setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _purchase,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText:
                        'سعر الشراء * (تكلفة الرول — للربح)'),
                validator: (v) =>
                    _reqNum(v, allowZero: true),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _unit,
                decoration: const InputDecoration(
                    labelText: 'الوحدة (رول / قطعة ...)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('الحجم',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _length,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText: 'الطول *'),
                      validator: (v) => _reqNum(v),
                      onChanged: (_) =>
                          setState(() {}),
                    ),
                  ),
                  const SizedBox(
                      width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<
                        String>(
                      key: ValueKey(
                          'len-unit-$_lengthUnit'),
                      initialValue: _lengthUnit,
                      decoration:
                          const InputDecoration(
                              labelText: 'الوحدة'),
                      items: [
                        for (final u in customDimUnits)
                          DropdownMenuItem(
                              value: u,
                              child: Text(u,
                                  textDirection:
                                      TextDirection
                                          .ltr)),
                      ],
                      onChanged: (v) => setState(() =>
                          _lengthUnit = v ?? 'mm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _width,
                      keyboardType: const TextInputType
                          .numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                              labelText: 'العرض *'),
                      validator: (v) => _reqNum(v),
                      onChanged: (_) =>
                          setState(() {}),
                    ),
                  ),
                  const SizedBox(
                      width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<
                        String>(
                      key: ValueKey(
                          'wid-unit-$_widthUnit'),
                      initialValue: _widthUnit,
                      decoration:
                          const InputDecoration(
                              labelText: 'الوحدة'),
                      items: [
                        for (final u in customDimUnits)
                          DropdownMenuItem(
                              value: u,
                              child: Text(u,
                                  textDirection:
                                      TextDirection
                                          .ltr)),
                      ],
                      onChanged: (v) => setState(() =>
                          _widthUnit = v ?? 'mm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // الخامة من بكر الباركود (بدل الكتابة اليدوية).
              matsAsync.when(
                loading: () => const LoadingSkeleton(
                    rows: 1),
                error: (_, _) => const Text(
                    'تعذر تحميل الخامات — تأكد من الاتصال.'),
                data: (mats) {
                  final comp =
                      _computedPrices(mats);
                  return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _materialId,
                      decoration:
                          const InputDecoration(
                              labelText:
                                  'الخامة * (من بكر الباركود)'),
                      items: [
                        for (final m in mats)
                          DropdownMenuItem(
                              value: m.id,
                              child:
                                  Text(m.display)),
                      ],
                      onChanged: (v) => setState(
                          () => _materialId = v),
                      validator: (v) =>
                          v == null || v.isEmpty
                              ? 'اختار الخامة'
                              : null,
                    ),
                    if (comp.sale > 0 ||
                        comp.purchase > 0)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                                top: 4),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [
                            Text(
                              'المحسوب من الخامة (÷ ${_divisor.text.trim().isEmpty ? '…' : _divisor.text.trim()}): شراء ${comp.purchase.toStringAsFixed(2)} • بيع ${comp.sale.toStringAsFixed(2)} جنيه',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.grey),
                              textDirection:
                                  TextDirection.rtl,
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() =>
                                          _purchase.text =
                                              comp.purchase
                                                  .toStringAsFixed(
                                                      2)),
                                  child: const Text(
                                      'استخدام سعر الشراء'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() =>
                                          _price.text =
                                              comp.sale
                                                  .toStringAsFixed(
                                                      2)),
                                  child: const Text(
                                      'استخدام سعر البيع'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _qtyPerRoll,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText:
                        'Quantity per Roll *'),
                validator: (v) => _reqNum(v),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _divisor,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText:
                        'معامل القسمة * (للحسبة من الخامة)'),
                validator: (v) => _reqNum(v),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: AppSpacing.md),
              matsAsync.maybeWhen(
                data: (mats) => FilledButton(
                  onPressed: () => _submit(mats),
                  child:
                      const Text('إضافة للفاتورة'),
                ),
                orElse: () => const FilledButton(
                  onPressed: null,
                  child: Text('إضافة للفاتورة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
