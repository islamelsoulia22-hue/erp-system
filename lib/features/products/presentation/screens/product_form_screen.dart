import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/validators.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';
import '../../../suppliers/data/suppliers_repository.dart';
import '../../../suppliers/domain/supplier.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';

/// Create / edit product. Guarded in UI by products.create/edit;
/// RLS enforces server-side.
class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  final _barcode = TextEditingController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _purchase = TextEditingController(text: '0');
  final _sale = TextEditingController(text: '0');
  final _minStock = TextEditingController(text: '0');
  final _openingQty = TextEditingController();
  // حقول أجهزة الإلكترونيات (تظهر بشروط الفئة).
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _deviceQty = TextEditingController();
  String? _deviceType;
  List<TextEditingController> _serialCtrls = [];
  bool _serialsLoaded = false;
  String? _categoryId;
  String? _unitId;
  String? _supplierId;
  // حقول بكر الباركود (فئة BARCODE_ROLL فقط).
  String? _materialId;
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _qtyRoll = TextEditingController();
  List<Supplier> _suppliers = [];
  String? _openingWarehouseId;
  List<Warehouse> _warehouses = [];
  List<StockLine> _stock = [];
  bool _loadingStock = false;
  bool _track = true;
  bool _customizable = false;
  bool _active = true;
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.productId != null;

  /// SKU داخلي فقط — لا يظهر في UI نهائيا، يتولد تلقائيا.
  String _genSku() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    return 'PRD-${ts.substring(ts.length - 6)}';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadWarehouses);
    // تأكد إن فئة بكر الباركود موجودة (تتعمل تلقائيا أول مرة).
    Future.microtask(_ensureRollCategory);
  }

  /// يعمل فئة بكر الباركود لو ناقصة وينعش قائمة الفئات.
  Future<void> _ensureRollCategory() async {
    try {
      // لو القائمة المحملة فيها الفئة فعلا مفيش داعي ننده السيرفر.
      final cached =
          ref.read(productCategoriesProvider).maybeWhen(
                data: (l) => l,
                orElse: () => null,
              );
      if (cached != null) {
        var found = false;
        for (final c in cached) {
          if (isBarcodeRollCategory(c)) {
            found = true;
            break;
          }
        }
        if (found) return;
      }
      final created = await ref
          .read(productsRepositoryProvider)
          .ensureBarcodeRollCategory();
      if (created != null && mounted) {
        ref.invalidate(productCategoriesProvider);
      }
    } catch (_) {}
  }

  Future<void> _loadWarehouses() async {
    try {
      final wh = await ref
          .read(warehousesRepositoryProvider)
          .list(onlyActive: true);
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        // لا نختار تلقائيا — اختيار المخزن إجباري عند إنشاء صنف.
      });
    } catch (e) {
      // كان silent قبل كده فالدروبداون كان بيبان فاضي من غير سبب واضح.
      debugPrint('product form warehouses error: $e (${e.runtimeType})');
    }
    try {
      final sup = await ref
          .read(suppliersRepositoryProvider)
          .search(query: '', pageSize: 100, onlyActive: true);
      if (!mounted) return;
      setState(() => _suppliers = sup);
    } catch (e) {
      debugPrint('product form suppliers error: $e (${e.runtimeType})');
    }
  }

  Future<void> _loadStock() async {
    if (!isEdit) return;
    setState(() => _loadingStock = true);
    try {
      final lines = await ref
          .read(warehousesRepositoryProvider)
          .stockOfProduct(widget.productId!);
      if (!mounted) return;
      setState(() => _stock = lines);
    } catch (_) {
      // الرصيد معلومة مساعدة فقط — لا نفشل الشاشة لو تعذر.
    } finally {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _scanBarcode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _barcode.text = code);
  }

  /// إضافة فئة جديدة من داخل الفورم (لو مش موجودة).
  Future<void> _addCategorySheet() async {
    final name = TextEditingController();
    final nameAr = TextEditingController();
    final created = await showModalBottomSheet<ProductCategory>(
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
            const Text('فئة جديدة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'اسم الفئة *')),
            const SizedBox(height: 8),
            TextField(
                controller: nameAr,
                decoration: const InputDecoration(
                    labelText: 'الاسم بالعربي (اختياري)')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                try {
                  final c = await ref
                      .read(productsRepositoryProvider)
                      .createCategory(
                        name: name.text,
                        nameAr: nameAr.text,
                      );
                  ref.invalidate(productCategoriesProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop(c);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء الفئة.')));
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
      setState(() => _categoryId = created.id);
    }
  }

  /// إضافة وحدة جديدة من داخل الفورم (لو مش موجودة).
  Future<void> _addUnitSheet() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final created = await showModalBottomSheet<ProductUnit>(
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
            const Text('وحدة جديدة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: code,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'الكود * (مثال: PCS)')),
            const SizedBox(height: 8),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'الاسم * (مثال: قطعة)')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (code.text.trim().isEmpty ||
                    name.text.trim().isEmpty) {
                  return;
                }
                try {
                  final u = await ref
                      .read(productsRepositoryProvider)
                      .createUnit(
                        code: code.text,
                        name: name.text,
                      );
                  ref.invalidate(productUnitsProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop(u);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء الوحدة — ربما الكود مكرر.')));
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
      setState(() => _unitId = created.id);
    }
  }

  @override
  void dispose() {
    _barcode.dispose();
    _name.dispose();
    _desc.dispose();
    _purchase.dispose();
    _sale.dispose();
    _minStock.dispose();
    _openingQty.dispose();
    _brand.dispose();
    _model.dispose();
    _deviceQty.dispose();
    _length.dispose();
    _width.dispose();
    _qtyRoll.dispose();
    for (final c in _serialCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// هل الفئة المختارة إلكترونيات؟ (من القائمة المحملة).
  bool _isElectronics(List<ProductCategory> cats) {
    if (_categoryId == null) return false;
    for (final c in cats) {
      if (c.id == _categoryId) return isElectronicsCategory(c);
    }
    return false;
  }

  /// هل الفئة المختارة بكر باركود؟ (تظهر حقول الخامة والمقاس).
  bool _isBarcodeRoll(List<ProductCategory> cats) {
    if (_categoryId == null) return false;
    for (final c in cats) {
      if (c.id == _categoryId) return isBarcodeRollCategory(c);
    }
    return false;
  }

  BarcodeMaterial? _selectedMaterial(
      List<BarcodeMaterial> mats) {
    if (_materialId == null) return null;
    for (final m in mats) {
      if (m.id == _materialId) return m;
    }
    return null;
  }

  /// حسبة سعر البكرة تلقائيا:
  /// شراء = سعر خامة الشراء × (طول+3) × (عرض+3) × العدد
  /// بيع = سعر خامة البيع × (طول+3) × (عرض+3) × العدد
  ({double purchase, double sale}) _rollPrices(
      List<BarcodeMaterial> mats) {
    final m = _selectedMaterial(mats);
    final len =
        double.tryParse(_length.text.trim()) ?? 0;
    final wid =
        double.tryParse(_width.text.trim()) ?? 0;
    final qty =
        double.tryParse(_qtyRoll.text.trim()) ?? 0;
    if (m == null) return (purchase: 0, sale: 0);
    return (
      purchase: BarcodeRollPricing.rollPrice(
          m.purchasePrice, len, wid, qty),
      sale: BarcodeRollPricing.rollPrice(
          m.salePrice, len, wid, qty),
    );
  }

  /// إضافة خامة جديدة من داخل الفورم (زرار إضافة خامة).
  Future<void> _addMaterialSheet() async {
    final nameAr = TextEditingController();
    final pur = TextEditingController(text: '0');
    final sal = TextEditingController(text: '0');
    final created = await showModalBottomSheet<
        BarcodeMaterial>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx)
                    .viewInsets.bottom +
                16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text('خامة جديدة',
                style: TextStyle(
                    fontWeight:
                        FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: nameAr,
                decoration:
                    const InputDecoration(
                        labelText:
                            'اسم الخامة * (مثال: نص لميع)')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pur,
                    keyboardType: const TextInputType
                        .numberWithOptions(
                            decimal: true),
                    textDirection:
                        TextDirection.ltr,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سعر الشراء *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: sal,
                    keyboardType: const TextInputType
                        .numberWithOptions(
                            decimal: true),
                    textDirection:
                        TextDirection.ltr,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سعر البيع *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'سعر الخامة ثابت — أي بكرة تختار الخامة دي هتحسب بسعرها تلقائيا.',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (nameAr.text
                    .trim()
                    .isEmpty) {
                  return;
                }
                final pp = double.tryParse(
                        pur.text.trim()) ??
                    -1;
                final sp = double.tryParse(
                        sal.text.trim()) ??
                    -1;
                if (pp < 0 || sp < 0) return;
                try {
                  final mat = await ref
                      .read(
                          productsRepositoryProvider)
                      .createMaterial(
                        nameAr: nameAr.text,
                        purchasePrice: pp,
                        salePrice: sp,
                      );
                  ref.invalidate(
                      barcodeMaterialsProvider);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(mat);
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(
                            content: Text(e
                                    is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء الخامة.')));
                  }
                }
              },
              child:
                  const Text('إنشاء واختيار'),
            ),
          ],
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() => _materialId = created.id);
    }
  }

  /// تعديل سعر الخامة المحفوظ (شراء/بيع) — الحسبة بتتحدث تلقائيا.
  Future<void> _editMaterialSheet(
      BarcodeMaterial mat) async {
    final pur = TextEditingController(
        text: mat.purchasePrice.toString());
    final sal = TextEditingController(
        text: mat.salePrice.toString());
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx)
                    .viewInsets.bottom +
                16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Text('سعر الخامة: ${mat.display}',
                style: const TextStyle(
                    fontWeight:
                        FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pur,
                    keyboardType: const TextInputType
                        .numberWithOptions(
                            decimal: true),
                    textDirection:
                        TextDirection.ltr,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سعر الشراء *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: sal,
                    keyboardType: const TextInputType
                        .numberWithOptions(
                            decimal: true),
                    textDirection:
                        TextDirection.ltr,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سعر البيع *'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final pp = double.tryParse(
                        pur.text.trim()) ??
                    -1;
                final sp = double.tryParse(
                        sal.text.trim()) ??
                    -1;
                if (pp < 0 || sp < 0) return;
                try {
                  await ref
                      .read(
                          productsRepositoryProvider)
                      .updateMaterial(
                        mat.id,
                        purchasePrice: pp,
                        salePrice: sp,
                      );
                  ref.invalidate(
                      barcodeMaterialsProvider);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(
                            content: Text(e
                                    is AppFailure
                                ? e.messageAr
                                : 'تعذر حفظ السعر.')));
                  }
                }
              },
              child: const Text('حفظ السعر'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  /// ظبط عدد حقول السيريال حسب الكمية مع الحفاظ على المدخل.
  void _syncSerialCtrls() {
    final n = int.tryParse(_deviceQty.text.trim()) ?? 0;
    if (n <= 0 || n > 200) return;
    if (_serialCtrls.length == n) return;
    final next = <TextEditingController>[];
    for (var i = 0; i < n; i++) {
      if (i < _serialCtrls.length) {
        next.add(_serialCtrls[i]);
      } else {
        next.add(TextEditingController());
      }
    }
    for (var i = n; i < _serialCtrls.length; i++) {
      _serialCtrls[i].dispose();
    }
    _serialCtrls = next;
  }

  Future<void> _prefill() async {
    if (!isEdit || _loaded) return;
    final p =
        await ref.read(productDetailProvider(widget.productId!).future);
    if (p == null || !mounted) return;
    _name.text = p.name;
    _desc.text = p.description ?? '';
    _purchase.text = p.purchasePrice.toString();
    _sale.text = p.salePrice.toString();
    _minStock.text = p.minimumStock.toString();
    _brand.text = p.brand ?? '';
    _model.text = p.model ?? '';
    if (p.labelLengthMm != null) {
      _length.text = p.labelLengthMm.toString();
    }
    if (p.labelWidthMm != null) {
      _width.text = p.labelWidthMm.toString();
    }
    if (p.qtyPerRoll != null) {
      _qtyRoll.text =
          p.qtyPerRoll!.toStringAsFixed(0);
    }
    setState(() {
      _categoryId = p.categoryId;
      _unitId = p.unitId;
      _supplierId = p.supplierId;
      _deviceType = p.deviceType;
      _materialId = p.barcodeMaterialId;
      _track = p.trackInventory;
      _customizable = p.isCustomizable;
      _active = p.isActive;
      _loaded = true;
    });
    _loadStock();
    _loadSerials();
  }

  Future<void> _loadSerials() async {
    if (!isEdit || _serialsLoaded) return;
    _serialsLoaded = true;
    try {
      final serials = await ref
          .read(productsRepositoryProvider)
          .serialsOf(widget.productId!);
      if (!mounted) return;
      setState(() {
        for (final c in _serialCtrls) {
          c.dispose();
        }
        _serialCtrls = [
          for (final s in serials) TextEditingController(text: s),
        ];
        if (serials.isNotEmpty) {
          _deviceQty.text = serials.length.toString();
        }
      });
    } catch (_) {
      // السيريالات معلومة إضافية — لا نفشل الشاشة لو تعذرت.
    }
  }

  double get _totalStock =>
      _stock.fold(0, (s, l) => s + l.quantity);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    // المخزن إجباري عند إنشاء صنف جديد (حتى لو الكمية صفر).
    if (!isEdit && _openingWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_warehouses.isEmpty
                  ? 'لا توجد مخازن — أنشئ مخزن أولا من صفحة المخازن.'
                  : 'اختر المخزن إجباريا.')));
      return;
    }
    // تحقق حقول الإلكترونيات (فئة إلكترونيات فقط).
    var cats = ref.read(productCategoriesProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <ProductCategory>[],
        );
    // لو البروفايدر لسه محملش (أول فتح) هات الفئات مباشرة عشان
    // تحديد فئة البكرة ميضعش.
    if (cats.isEmpty && _categoryId != null) {
      try {
        cats = await ref
            .read(productsRepositoryProvider)
            .categories();
      } catch (_) {}
    }
    final showDevice =
        _isElectronics(cats) || _deviceType != null;
    final showRoll = _isBarcodeRoll(cats);
    // تحقق حقول بكر الباركود + حسبة سعر البكرة تلقائيا.
    double rollPurchase = 0;
    double rollSale = 0;
    double? lenMm;
    double? widMm;
    double? qtyRoll;
    if (showRoll) {
      if (_materialId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('اختر نوع الخامة أولا.')));
        return;
      }
      lenMm =
          double.tryParse(_length.text.trim());
      widMm =
          double.tryParse(_width.text.trim());
      qtyRoll =
          double.tryParse(_qtyRoll.text.trim());
      if (lenMm == null ||
          lenMm <= 0 ||
          widMm == null ||
          widMm <= 0 ||
          qtyRoll == null ||
          qtyRoll <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'ادخل الطول والعرض بالملي وعدد الاستيكرات (qty/roll) أكبر من صفر.')));
        return;
      }
      // سعر الخامة ثابت ومحفوظ — نجيبه من القائمة المحملة.
      final mats = ref
          .read(barcodeMaterialsProvider)
          .maybeWhen(
            data: (l) => l,
            orElse: () =>
                const <BarcodeMaterial>[],
          );
      BarcodeMaterial? mat;
      for (final m in mats) {
        if (m.id == _materialId) {
          mat = m;
          break;
        }
      }
      mat ??= await ref
          .read(productsRepositoryProvider)
          .barcodeMaterials()
          .then((l) {
            for (final m in l) {
              if (m.id == _materialId) return m;
            }
            return null;
          })
          .catchError((_) => null);
      if (mat == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('تعذر تحميل سعر الخامة — حدّث الصفحة وحاول مجددا.')));
        return;
      }
      rollPurchase =
          BarcodeRollPricing.rollPrice(
              mat.purchasePrice,
              lenMm,
              widMm,
              qtyRoll);
      rollSale = BarcodeRollPricing.rollPrice(
          mat.salePrice, lenMm, widMm, qtyRoll);
    }
    List<String> serials = [];
    if (showDevice) {
      // كل حقول الجهاز اختيارية: النوع / الماركة / الموديل / العدد / السيريالات.
      final qtyText = _deviceQty.text.trim();
      if (qtyText.isNotEmpty) {
        final qty = int.tryParse(qtyText);
        if (qty == null || qty <= 0 || qty > 200) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('عدد الأجهزة يجب أن يكون رقما من 1 لـ 200 — أو سيبه فاضي.')));
          return;
        }
      }
      // السيريال اختياري تماما: الفاضي يتجاهل، ونتحقق فقط من تكرار المدخل فعلا.
      serials = [
        for (final c in _serialCtrls)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ];
      if (serials.toSet().length != serials.length) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('السيريالات مكررة — راجعها.')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(productsRepositoryProvider);
      final brand = _brand.text.trim();
      final model = _model.text.trim();
      final deviceData = showDevice
          ? {
              'device_type': _deviceType,
              'brand': brand.isEmpty ? null : brand,
              'model': model.isEmpty ? null : model,
            }
          : {
              'device_type': null,
              'brand': null,
              'model': null,
            };
      if (isEdit) {
        // تعديل: الضريبة وSKU خارج الفورم — نحافظ على القيم القديمة.
        // لو بكر باركود: سعر الشراء/البيع = سعر البكرة المحسوب تلقائيا.
        final data = {
          'name': _name.text.trim(),
          'description':
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'category_id': _categoryId,
          'unit_id': _unitId,
          'supplier_id': _supplierId,
          ...deviceData,
          'purchase_price': showRoll
              ? rollPurchase
              : double.parse(_purchase.text),
          'sale_price': showRoll
              ? rollSale
              : double.parse(_sale.text),
          'barcode_material_id':
              showRoll ? _materialId : null,
          'label_length_mm': showRoll ? lenMm : null,
          'label_width_mm': showRoll ? widMm : null,
          'qty_per_roll': showRoll ? qtyRoll : null,
          'minimum_stock': double.parse(_minStock.text),
          'track_inventory': _track,
          'is_customizable': _customizable,
          'is_active': _active,
        };
        await repo.update(widget.productId!, data);
        if (showDevice) {
          await repo.replaceSerials(
              widget.productId!, serials);
        }
      } else {
        // صنف جديد: SKU داخلي تلقائي + الضريبة في الفاتورة فقط.
        final data = {
          'sku': _genSku(),
          'name': _name.text.trim(),
          'description':
              _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'category_id': _categoryId,
          'unit_id': _unitId,
          'supplier_id': _supplierId,
          ...deviceData,
          'purchase_price': showRoll
              ? rollPurchase
              : double.parse(_purchase.text),
          'sale_price': showRoll
              ? rollSale
              : double.parse(_sale.text),
          'barcode_material_id':
              showRoll ? _materialId : null,
          'label_length_mm': showRoll ? lenMm : null,
          'label_width_mm': showRoll ? widMm : null,
          'qty_per_roll': showRoll ? qtyRoll : null,
          'taxable': false,
          'tax_rate': 0,
          'minimum_stock': double.parse(_minStock.text),
          'track_inventory': _track,
          'is_customizable': _customizable,
          'is_active': _active,
        };
        final created = await repo.create(data);
        if (showDevice) {
          await repo.replaceSerials(created.id, serials);
        }
        // باركود اختياري: يدوي أو مسح — يتسجل كبريماري.
        final bc = _barcode.text.trim();
        if (bc.isNotEmpty) {
          try {
            await repo.addBarcode(
                productId: created.id, barcode: bc, isPrimary: true);
          } catch (_) {
            // لو الباركود مكرر نبلغ بس من غير ما نفشل إنشاء الصنف.
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'تم إنشاء الصنف لكن الباركود مكرر ولم يُحفظ.')));
            }
          }
        }
        // الكمية الحالية (اختياري): لو كتب كمية بتتسجل في المخزن
        // اللي اختاره، وفواتير المشتريات بعد كده بتتضاف عليها.
        final opening =
            double.tryParse(_openingQty.text.trim()) ?? 0;
        if (opening > 0 && _openingWarehouseId != null) {
          try {
            await ref
                .read(warehousesRepositoryProvider)
                .adjust(
                  warehouseId: _openingWarehouseId!,
                  productId: created.id,
                  qtyChange: opening,
                  notes: 'رصيد افتتاحي',
                );
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'تم إنشاء الصنف لكن الكمية لم تُحفظ — المستخدم محتاج صلاحية تسوية المخزون (inventory.adjust).')));
            }
          }
        }
      }
      ref
        ..invalidate(productsPageProvider)
        ..invalidate(productDetailProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AppFailure
          ? e.messageAr
          : 'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(productCategoriesProvider);
    final units = ref.watch(productUnitsProvider);
    final mats = ref.watch(barcodeMaterialsProvider);
    if (isEdit && !_loaded) {
      _prefill();
    }
    final catList = cats.maybeWhen(
      data: (l) => l,
      orElse: () => const <ProductCategory>[],
    );
    final showDevice =
        _isElectronics(catList) || _deviceType != null;
    final showRoll = _isBarcodeRoll(catList);
    final matList = mats.maybeWhen(
      data: (l) => l,
      orElse: () => const <BarcodeMaterial>[],
    );
    final roll = _rollPrices(matList);
    final selMat = _selectedMaterial(matList);

    return Scaffold(
            body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isEdit) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('الكمية الحالية بالمخازن',
                              style: TextStyle(
                                  fontWeight:
                                      FontWeight.bold)),
                          const Spacer(),
                          if (_loadingStock)
                            const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(
                                      strokeWidth: 2),
                            )
                          else
                            Text(
                              'الإجمالي: ${_totalStock.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight:
                                      FontWeight.bold),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!_loadingStock &&
                          _stock.isEmpty)
                        const Text(
                          'لا يوجد رصيد مسجل — الكمية صفر.',
                          style: TextStyle(
                              color: Colors.grey),
                        ),
                      for (final s in _stock)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                                  vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      s.warehouseName)),
                              Text(
                                '${s.quantity.toStringAsFixed(0)} (متاح ${s.available.toStringAsFixed(0)})',
                                textDirection:
                                    TextDirection.ltr,
                                style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!isEdit)
              TextFormField(
                controller: _barcode,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الباركود (يدوي أو مسح)',
                  prefixIcon:
                      const Icon(Icons.barcode_reader),
                  suffixIcon: IconButton(
                    tooltip: 'مسح باركود',
                    icon: const Icon(
                        Icons.qr_code_scanner_outlined),
                    onPressed: _scanBarcode,
                  ),
                ),
              ),
            if (!isEdit) const SizedBox(height: 12),
            TextFormField(
                controller: _name,
                decoration:
                    const InputDecoration(labelText: 'اسم المنتج *'),
                validator: Validators.required),
            const SizedBox(height: 12),
            TextFormField(
                controller: _desc,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'الوصف')),
            const SizedBox(height: 12),
            cats.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('تعذر تحميل الفئات: $e'),
              data: (list) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('cat-$_categoryId'),
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                          labelText: 'الفئة (اختياري)'),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('بدون فئة')),
                        for (final c in list)
                          DropdownMenuItem(
                              value: c.id,
                              child: Text(c.display)),
                      ],
                      onChanged: (v) => setState(() {
                        _categoryId = v;
                        // لو خرج من الإلكترونيات امسح اختيار الجهاز.
                        if (!_isElectronics(list)) {
                          _deviceType = null;
                        }
                        // لو خرج من بكر الباركود امسح اختيار الخامة
                        // عشان الحفظ ميطلبش حقول البكرة.
                        if (!_isBarcodeRoll(list)) {
                          _materialId = null;
                        }
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'فئة جديدة',
                    icon: const Icon(Icons.add_outlined),
                    onPressed: _addCategorySheet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            units.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('تعذر تحميل الوحدات: $e'),
              data: (list) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('unit-$_unitId'),
                      initialValue: _unitId,
                      decoration: const InputDecoration(
                          labelText: 'الوحدة (اختياري)'),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('بدون وحدة')),
                        for (final u in list)
                          DropdownMenuItem(
                              value: u.id,
                              child: Text(
                                  '${u.display} (${u.code})')),
                      ],
                      onChanged: (v) =>
                          setState(() => _unitId = v),
                    ),
                  ),
                  IconButton(
                    tooltip: 'وحدة جديدة',
                    icon: const Icon(Icons.add_outlined),
                    onPressed: _addUnitSheet,
                  ),
                ],
              ),
            ),
            if (showRoll) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'بيانات بكر الباركود (Barcode Sticker)',
                        style: TextStyle(
                            fontWeight:
                                FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اختر الخامة ثم ادخل الطول والعرض بالملي وعدد الاستيكرات — سعر البكرة يتحسب تلقائيا.',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      mats.when(
                        loading: () => const Center(
                            child:
                                CircularProgressIndicator()),
                        error: (e, _) => Text(
                            'تعذر تحميل الخامات: $e'),
                        data: (list) => Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                      String>(
                                key: ValueKey(
                                    'mat-$_materialId'),
                                initialValue:
                                    _materialId,
                                decoration:
                                    const InputDecoration(
                                        labelText:
                                            'نوع الخامة *'),
                                items: [
                                  for (final m
                                      in list)
                                    DropdownMenuItem(
                                        value: m.id,
                                        child: Text(
                                            m.display)),
                                ],
                                validator: (v) =>
                                    showRoll &&
                                            v == null
                                        ? 'اختر الخامة'
                                        : null,
                                onChanged: (v) =>
                                    setState(() =>
                                        _materialId =
                                            v),
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  'إضافة خامة',
                              icon: const Icon(Icons
                                  .add_outlined),
                              onPressed:
                                  _addMaterialSheet,
                            ),
                          ],
                        ),
                      ),
                      if (selMat != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding:
                              const EdgeInsets.all(
                                  8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(
                                    8),
                            border: Border.all(
                                color: Colors.grey
                                    .shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'سعر الخامة شراء: ${selMat.purchasePrice}',
                                  textDirection:
                                      TextDirection
                                          .ltr,
                                  style: const TextStyle(
                                      fontSize: 12),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'بيع: ${selMat.salePrice}',
                                  textDirection:
                                      TextDirection
                                          .ltr,
                                  style: const TextStyle(
                                      fontSize: 12),
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'تعديل سعر الخامة',
                                iconSize: 20,
                                icon: const Icon(Icons
                                    .edit_outlined),
                                onPressed: () =>
                                    _editMaterialSheet(
                                        selMat),
                              ),
                            ],
                          ),
                        ),
                        if (selMat.purchasePrice <=
                                0 ||
                            selMat.salePrice <= 0) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'سعر الخامة صفر — دوس على القلم وادخل سعر الشراء والبيع عشان الحسبة تطلع صح.',
                            style: TextStyle(
                                color: Colors
                                    .deepOrange,
                                fontSize: 12),
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _length,
                              keyboardType: const TextInputType
                                  .numberWithOptions(
                                      decimal:
                                          true),
                              textDirection:
                                  TextDirection.ltr,
                              decoration:
                                  const InputDecoration(
                                      labelText:
                                          'الطول بالملي *'),
                              validator: (v) {
                                if (!showRoll) {
                                  return null;
                                }
                                final d =
                                    double.tryParse(
                                        (v ?? '')
                                            .trim());
                                if (d == null ||
                                    d <= 0) {
                                  return 'أدخل الطول';
                                }
                                return null;
                              },
                              onChanged: (_) =>
                                  setState(
                                      () {}),
                            ),
                          ),
                          const SizedBox(
                              width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _width,
                              keyboardType: const TextInputType
                                  .numberWithOptions(
                                      decimal:
                                          true),
                              textDirection:
                                  TextDirection.ltr,
                              decoration:
                                  const InputDecoration(
                                      labelText:
                                          'العرض بالملي *'),
                              validator: (v) {
                                if (!showRoll) {
                                  return null;
                                }
                                final d =
                                    double.tryParse(
                                        (v ?? '')
                                            .trim());
                                if (d == null ||
                                    d <= 0) {
                                  return 'أدخل العرض';
                                }
                                return null;
                              },
                              onChanged: (_) =>
                                  setState(
                                      () {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _qtyRoll,
                        keyboardType: const TextInputType
                            .numberWithOptions(
                                decimal: false),
                        textDirection:
                            TextDirection.ltr,
                        decoration:
                            const InputDecoration(
                                labelText:
                                    'qty/roll (عدد الاستيكرات) *'),
                        validator: (v) {
                          if (!showRoll) {
                            return null;
                          }
                          final d =
                              double.tryParse(
                                  (v ?? '').trim());
                          if (d == null ||
                              d <= 0) {
                            return 'أدخل العدد';
                          }
                          return null;
                        },
                        onChanged: (_) =>
                            setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding:
                            const EdgeInsets.all(
                                10),
                        decoration: BoxDecoration(
                          color: Colors.green
                              .shade50,
                          borderRadius:
                              BorderRadius.circular(
                                  8),
                          border: Border.all(
                              color: Colors.green
                                  .shade200),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [
                            Text(
                              'سعر البكرة شراء: ${roll.purchase.toStringAsFixed(2)}',
                              textDirection:
                                  TextDirection
                                      .ltr,
                              style: const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold),
                            ),
                            Text(
                              'سعر البكرة بيع: ${roll.sale.toStringAsFixed(2)}',
                              textDirection:
                                  TextDirection
                                      .ltr,
                              style: const TextStyle(
                                  fontWeight:
                                      FontWeight
                                          .bold),
                            ),
                            const SizedBox(
                                height: 4),
                            const Text(
                              'الحسبة = سعر الخامة × (الطول+3) × (العرض+3) × العدد — وتتسجل تلقائيا كسعر شراء/بيع للصنف.',
                              style: TextStyle(
                                  color:
                                      Colors.grey,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (showDevice) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'بيانات الجهاز (فئة إلكترونيات)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                            'device-$_deviceType'),
                        initialValue: _deviceType,
                        decoration: const InputDecoration(
                            labelText: 'نوع الجهاز (اختياري)'),
                        items: [
                          for (final t in DeviceTypes.all)
                            DropdownMenuItem(
                                value: t,
                                child: Text(
                                    DeviceTypes.labelOf(t))),
                        ],
                        onChanged: (v) => setState(
                            () => _deviceType = v),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _brand,
                              decoration:
                                  const InputDecoration(
                                      labelText:
                                          'الماركة (Brand) (اختياري)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _model,
                              decoration:
                                  const InputDecoration(
                                      labelText:
                                          'الموديل (Model) (اختياري)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _deviceQty,
                        keyboardType: const TextInputType
                            .numberWithOptions(
                                decimal: false),
                        textDirection:
                            TextDirection.ltr,
                        decoration: const InputDecoration(
                            labelText:
                                'عدد الأجهزة (اختياري — تظهر حقول السيريال حسبه)'),
                        onChanged: (_) => setState(
                            () => _syncSerialCtrls()),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0;
                          i < _serialCtrls.length;
                          i++)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                                  bottom: 8),
                          child: TextFormField(
                            controller:
                                _serialCtrls[i],
                            textDirection:
                                TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText:
                                  'سيريال جهاز ${i + 1} (اختياري)',
                              hintText: 'اختياري',
                              prefixIcon: const Icon(
                                  Icons
                                      .qr_code_outlined,
                                  size: 18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _supplierId,
              decoration: const InputDecoration(
                  labelText: 'المورد (اختياري)',
                  helperText:
                      'سيبه فاضي لو الصنف من مورد نقدي أو بدون مورد ثابت'),
              items: [
                for (final s in _suppliers)
                  DropdownMenuItem(
                      value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) =>
                  setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),
            if (showRoll)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'سعر الشراء والبيع للبكرة يتحسب تلقائيا من الخامة والمقاس والعدد — لا تدخلهم يدويا.',
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                        controller: _purchase,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                            labelText: 'سعر الشراء'),
                        validator: Validators.quantity),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                        controller: _sale,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                            labelText: 'سعر البيع'),
                        validator: Validators.quantity),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _minStock,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'الحد الأدنى'),
                validator: Validators.required),
            SwitchListTile(
                title: const Text('تتبع المخزون'),
                value: _track,
                onChanged: (v) => setState(() => _track = v)),
            SwitchListTile(
                title: const Text('قابل للتخصيص'),
                value: _customizable,
                onChanged: (v) =>
                    setState(() => _customizable = v)),
            SwitchListTile(
                title: const Text('نشط'),
                value: _active,
                onChanged: (v) =>
                    setState(() => _active = v)),
            if (!isEdit) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'المخزن والكمية الافتتاحية',
                        style: TextStyle(
                            fontWeight:
                                FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اختيار المخزن إجباري لكل صنف جديد. لو عندك كمية موجودة فعلا اكتبها وهتتسجل في المخزن اللي اخترته، ولو مفيش سيب الكمية فاضية (صفر). المشتريات بعد كده بتتضاف عليها عند الاستلام.',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _openingWarehouseId,
                        decoration:
                            InputDecoration(
                                labelText: 'المخزن *',
                                hintText:
                                    _warehouses.isEmpty
                                        ? 'لا توجد مخازن — أنشئ مخزن أولا'
                                        : null),
                        items: [
                          for (final w
                              in _warehouses)
                            DropdownMenuItem(
                                value: w.id,
                                child: Text(
                                    '${w.name} (${w.code})')),
                        ],
                        validator: (v) {
                          if (_warehouses.isEmpty) {
                            return 'لا توجد مخازن — أنشئ مخزن أولا';
                          }
                          return v == null
                              ? 'اختر المخزن إجباريا'
                              : null;
                        },
                        onChanged: (v) => setState(() =>
                            _openingWarehouseId =
                                v),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _openingQty,
                          keyboardType: const TextInputType
                              .numberWithOptions(
                                  decimal: true),
                          textDirection:
                              TextDirection.ltr,
                          decoration:
                              const InputDecoration(
                                  labelText:
                                      'الكمية (فاضي = بدون رصيد)'),
                          validator: (v) {
                            if (v == null ||
                                v.trim().isEmpty) {
                              return null;
                            }
                            return Validators
                                .quantity(v);
                          }),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child:
                          CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'حفظ' : 'إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}
