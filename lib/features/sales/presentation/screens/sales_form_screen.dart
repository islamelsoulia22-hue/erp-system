import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/yad_widgets.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../customers/data/customers_repository.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../shipping/data/shipping_repository.dart';
import '../../../shortages/data/shortages_repository.dart';
import '../widgets/reservation_flow.dart';
import '../../../manufacturing/data/customized_from_invoice.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/sales_repository.dart';
import '../../domain/sales.dart';
import '../providers/sales_providers.dart';
import '../widgets/barcode_scan_sheet.dart';
import '../widgets/custom_item_sheet.dart';
import '../widgets/serial_pick_sheet.dart';

class _CartLine {
  final String? productId;
  final String name;
  final String? sku;
  double qty;
  double price;
  double cost;
  double taxRate;
  // الصنف الخاص (null للعادي).
  final bool isCustom;
  final String? customUnit;
  final double? lengthValue;
  final String? lengthUnit;
  final double? widthValue;
  final String? widthUnit;
  final String? rawMaterialId;
  final String? rawMaterialName;
  final double? qtyPerRoll;
  final String? customNotes;
  // سيريالات العميل (أصناف إلكترونية فقط) — تتسجل عند الاعتماد.
  List<String> serials;
  final bool isElectronics;
  _CartLine({
    this.productId,
    required this.name,
    this.sku,
    required this.qty,
    required this.price,
    this.cost = 0,
    required this.taxRate,
    this.isCustom = false,
    this.customUnit,
    this.lengthValue,
    this.lengthUnit,
    this.widthValue,
    this.widthUnit,
    this.rawMaterialId,
    this.rawMaterialName,
    this.qtyPerRoll,
    this.customNotes,
    List<String>? serials,
    this.isElectronics = false,
  }) : serials = serials ?? [];

  String get specSummary {
    if (!isCustom) return '';
    final parts = <String>[];
    if (lengthValue != null && widthValue != null) {
      parts.add(
          '${_f(lengthValue!)} × ${_f(widthValue!)} ${lengthUnit ?? widthUnit ?? ''}'
              .trim());
    }
    if (rawMaterialName?.isNotEmpty == true) {
      parts.add(rawMaterialName!);
    }
    if (qtyPerRoll != null) {
      parts.add('Qty/Roll: ${_f(qtyPerRoll!)}');
    }
    return parts.join(' • ');
  }

  static String _f(double v) =>
      v == v.truncateToDouble() ? v.truncate().toString() : v.toString();
}

class SalesFormScreen extends ConsumerStatefulWidget {
  const SalesFormScreen({super.key});

  @override
  ConsumerState<SalesFormScreen> createState() => _SalesFormScreenState();
}

class _SalesFormScreenState extends ConsumerState<SalesFormScreen> {
  final _form = GlobalKey<FormState>();
  final _ref = TextEditingController();
  final _walkIn = TextEditingController();
  final _creditReason = TextEditingController();
  final _globalTaxCtrl = TextEditingController(text: '14');
  // تفاصيل الشحن (تظهر وتتملى مع الفاتورة لو التوصيل شحن).
  final _shipCompany = TextEditingController();
  final _shipName = TextEditingController();
  final _shipPhone = TextEditingController();
  final _shipAddress = TextEditingController();
  final _shipCity = TextEditingController();
  final _shipCost = TextEditingController(text: '0');
  String? _customerId;
  String? _customerName;
  String? _warehouseId;
  String? _paymentId;
  String _delivery = 'OFFICE_PICKUP';
  // ضريبة عامة على الفاتورة كلها بدل حقل لكل صنف.
  bool _hasTax = false;
  double _globalTaxRate = 14;
  final _cart = <_CartLine>[];
  bool _saving = false;
  List<Warehouse> _warehouses = [];
  List<Map<String, dynamic>> _payMethods = [];
  // المتاح الحالي لكل صنف في المخزن المختار (يتحدث مع السلة/المخزن).
  // الخصم لا يتم إلا عند اعتماد المدير — هنا عرض وتحذير فقط.
  Map<String, double> _avail = {};
  // فئة الإلكترونيات (الطابعات) — بنودها تختار سيريال العميل.
  String? _elecCatId;
  // بعد الحفظ: هل طلب حجز المتاح + توريد الناقص تلقائيا؟
  bool _autoRequestSupply = false;

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
      String? elecId;
      try {
        final cats = await ref
            .read(productsRepositoryProvider)
            .categories();
        for (final c in cats) {
          if (isElectronicsCategory(c)) {
            elecId = c.id;
            break;
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        _payMethods = pm;
        _elecCatId = elecId;
        if (wh.isNotEmpty) _warehouseId = wh.first.id;
        final cash = pm.where((e) => e['code'] == 'CASH').toList();
        if (cash.isNotEmpty) _paymentId = cash.first['id'] as String?;
      });
      _refreshAvail();
    } catch (_) {}
  }

  /// يحدث خريطة المتاح للسلة الحالية من المخزن المختار.
  /// قراءة فقط — لا يحجز ولا يخصم (الحجز عند اعتماد المدير).
  Future<void> _refreshAvail() async {
    final whId = _warehouseId;
    if (whId == null) return;
    try {
      final stock =
          await ref.read(warehousesRepositoryProvider).stockOf(whId);
      if (!mounted) return;
      setState(() {
        _avail = {for (final s in stock) s.productId: s.available};
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _ref.dispose();
    _walkIn.dispose();
    _creditReason.dispose();
    _globalTaxCtrl.dispose();
    _shipCompany.dispose();
    _shipName.dispose();
    _shipPhone.dispose();
    _shipAddress.dispose();
    _shipCity.dispose();
    _shipCost.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _cart.fold(0, (s, l) => s + l.qty * l.price);
  double get _taxTotal => _hasTax
      ? _cart.fold(
          0, (s, l) => s + (l.qty * l.price) * _globalTaxRate / 100)
      : 0;
  double get _grandTotal => _subtotal + _taxTotal;

  void _applyGlobalTaxToCart() {
    for (final l in _cart) {
      l.taxRate = _hasTax ? _globalTaxRate : 0;
    }
  }

  void _onTaxToggle(bool? v) {
    setState(() {
      _hasTax = v ?? false;
      _applyGlobalTaxToCart();
    });
  }

  void _onGlobalTaxChanged(String v) {
    final d = double.tryParse(v);
    if (d == null || d < 0 || d > 100) return;
    setState(() {
      _globalTaxRate = d;
      if (_hasTax) _applyGlobalTaxToCart();
    });
  }

  void _merge(Product p, double qty) {
    final i =
        _cart.indexWhere((l) => l.productId == p.id);
    final isElec =
        _elecCatId != null && p.categoryId == _elecCatId;
    setState(() {
      if (i >= 0) {
        _cart[i].qty += qty; // نفس الباركود يتجمع quantity
      } else {
        _cart.add(_CartLine(
          productId: p.id,
          name: p.name,
          sku: p.sku,
          qty: qty,
          price: p.salePrice,
          // الضريبة عامة على الفاتورة كلها (تشيك بوكس)، مش لكل صنف.
          taxRate: _hasTax ? _globalTaxRate : 0,
          isElectronics: isElec,
        ));
      }
    });
    _refreshAvail();
  }

  /// اختيار سيريالات العميل لسطر إلكتروني (طابعة).
  Future<void> _pickSerials(int i) async {
    final l = _cart[i];
    if (l.productId == null) return;
    final picked = await showSerialPickSheet(
      context,
      productId: l.productId!,
      qty: l.qty,
      initial: l.serials,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cart[i].serials =
          picked.take(l.qty.toInt().clamp(1, 100)).toList();
    });
  }

  Future<void> _scan() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty) return;
    try {
      final p = await ref
          .read(productsRepositoryProvider)
          .findByBarcode(code);
      if (!mounted) return;
      if (p == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('المنتج غير موجود.')));
        return;
      }
      _merge(p, 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'حدث خطأ أثناء البحث.')));
    }
  }

  /// إضافة صنف خاص (تصنيع) للفاتورة — بدون مخزون.
  Future<void> _addCustom() async {
    final spec = await showCustomItemSheet(context);
    if (spec == null || !mounted) return;
    setState(() {
      _cart.add(_CartLine(
        productId: null,
        name: spec.name,
        sku: null,
        qty: spec.qty,
        price: spec.price,
        cost: spec.purchasePrice,
        taxRate: _hasTax ? _globalTaxRate : 0,
        isCustom: true,
        customUnit: spec.unit,
        lengthValue: spec.length,
        lengthUnit: spec.lengthUnit,
        widthValue: spec.width,
        widthUnit: spec.widthUnit,
        rawMaterialId: null,
        rawMaterialName: spec.rawMaterialName,
        qtyPerRoll: spec.qtyPerRoll,
        customNotes: spec.notes,
      ));
    });
  }

  Future<void> _manualSearch() async {
    final q = TextEditingController();
    List<Product> results = [];
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
              const Text('بحث منتج بالاسم / SKU / باركود',
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
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.sku} • سعر البيع: ${AppFormat.money(p.salePrice)}',
                    textDirection: TextDirection.ltr,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppFormat.money(p.salePrice, suffix: ''),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        child: const Text('إضافة'),
                        onPressed: () {
                          _merge(p, 1);
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomer() async {
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
              const Text('اختيار عميل',
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
                        .read(customersRepositoryProvider)
                        .search(query: q.text, pageSize: 20);
                    setS(() {});
                  },
                ),
              ]),
              for (final c in results)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text(c.code),
                  onTap: () {
                    setState(() {
                      _customerId = c.id as String;
                      _customerName = c.name as String;
                      _walkIn.clear();
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _customerId = null;
                    _customerName = null;
                  });
                  Navigator.of(ctx).pop();
                },
                child:
                    const Text('عميل نقدي (بدون ملف)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// الشحن المختار مع الفاتورة: تفاصيله بتتملى هنا وبتتعمل
  /// شحنة PREPARING مربوطة تلقائيا بعد حفظ الفاتورة.
  bool get _needsShipping => _delivery == 'SHIPPING';

  String? _shippingError() {
    if (!_needsShipping) return null;
    if (_shipName.text.trim().isEmpty ||
        _shipPhone.text.trim().isEmpty ||
        _shipAddress.text.trim().isEmpty) {
      return 'الشحن يتطلب اسم المستلم والهاتف والعنوان.';
    }
    return null;
  }

  Future<void> _autoCreateShipment(String invoiceId) async {
    try {
      await ref.read(shippingRepositoryProvider).create({
        'sales_invoice_id': invoiceId,
        'customer_id': _customerId,
        'shipping_company':
            _shipCompany.text.trim().isEmpty
                ? null
                : _shipCompany.text.trim(),
        'recipient_name': _shipName.text.trim(),
        'recipient_phone': _shipPhone.text.trim(),
        'address': _shipAddress.text.trim(),
        'city': _shipCity.text.trim().isEmpty
            ? null
            : _shipCity.text.trim(),
        'shipping_cost':
            double.tryParse(_shipCost.text.trim()) ?? 0,
        'delivery_method': 'SHIPPING',
        'status': 'PREPARING',
      });
      ref.invalidate(shipmentsPageProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? 'اتحفظت الفاتورة بس الشحنة متعملتش: ${e.messageAr}'
              : 'اتحفظت الفاتورة بس الشحنة متعملتش.')));
    }
  }

  Future<void> _save() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أضف صنفا واحدا على الأقل.')));
      return;
    }
    if (_warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر المخزن.')));
      return;
    }
    if (_customerId == null && _walkIn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر عميلا أو أدخل اسم العميل النقدي.')));
      return;
    }
    final shipErr = _shippingError();
    if (shipErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(shipErr)));
      return;
    }
    // فحص المتاح قبل الحفظ: المتاح 15 والمطلوب 16 مثلا.
    final exceeding = await _exceedingLines();
    if (exceeding.isNotEmpty && mounted) {
      final ok = await _shortageDialog(exceeding);
      if (!ok || !mounted) return;
      if (_cart.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('السلة فارغة بعد التقليل للمتاح.')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(salesRepositoryProvider).createDraft(
            customerId: _customerId,
            customerName: _customerId == null
                ? _walkIn.text.trim()
                : null,
            warehouseId: _warehouseId,
            paymentMethodId: _paymentId,
            reference: _ref.text,
            delivery: _delivery,
            creditReason: _creditReason.text,
            items: [
              for (final l in _cart)
                SalesItemInput(
                  productId: l.productId,
                  itemName: l.name,
                  sku: l.sku,
                  quantity: l.qty,
                  unitPrice: l.price,
                  unitCost: l.cost,
                  serialNumbers: l.serials,
                  taxRate: l.taxRate,
                  itemType: l.isCustom ? 'CUSTOMIZED' : 'STANDARD',
                  customUnit: l.customUnit,
                  lengthValue: l.lengthValue,
                  lengthUnit: l.lengthUnit,
                  widthValue: l.widthValue,
                  widthUnit: l.widthUnit,
                  rawMaterialId: l.rawMaterialId,
                  rawMaterialName: l.rawMaterialName,
                  qtyPerRoll: l.qtyPerRoll,
                  customNotes: l.customNotes,
                ),
            ],
          );
      ref.invalidate(salesPageProvider);
      final shortages = await _checkShortages(id);
      var supplied = 0;
      if (_autoRequestSupply) {
        supplied = await _autoSupplyRequest(id);
      }
      _autoRequestSupply = false;
      if (_needsShipping) {
        await _autoCreateShipment(id);
      }
      if (mounted) {
        if (shortages > 0 || supplied > 0) {
          final parts = <String>[];
          if (shortages > 0) {
            parts.add(
                'واتسجل $shortages صنف في النواقص لعدم كفاية الرصيد');
          }
          if (supplied > 0) {
            parts.add(
                'واتعمل $supplied طلب توريد بالناقص وراح لاعتماد المدير');
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('تم حفظ المسودة، ${parts.join('، ')}.')));
        }
        // العربون للآجل أو الصنف الخاص فقط — مش للكاش.
        if (_shouldAskDeposit) {
          await _depositPrompt(id);
        } else {
          context.pushReplacement('/sales/$id');
        }
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

  void _dec(int i) {
    setState(() {
      _cart[i].qty -= 1;
      if (_cart[i].qty <= 0) _cart.removeAt(i);
    });
    _refreshAvail();
  }

  void _inc(int i) {
    setState(() => _cart[i].qty += 1);
    _refreshAvail();
  }

  void _remove(int i) {
    setState(() => _cart.removeAt(i));
    _refreshAvail();
  }
  // سعر البيع يتعدل على مستوى السطر فقط (يسمع في الفاتورة فقط،
  // ولا يحدث سعر الصنف في المخزن / جدول المنتجات).
  void _setPrice(int i, double v) => setState(() {
        _cart[i].price = v;
      });

  /// فحص النواقص بعد إنشاء الفاتورة: لو الكمية المطلوبة مش متاحة
  /// أو هتنزل تحت الحد الأدنى، بيسجل طلب تلقائي في النواقص
  /// (من مورد الصنف). الفشل هنا لا يوقف الفاتورة أبدا.
  /// بيرجع عدد الأصناف اللي اتسجلت.
  Future<int> _checkShortages(String invoiceId) async {
    try {
      final whId = _warehouseId;
      if (whId == null) return 0;
      final ids = [
        for (final l in _cart)
          if (l.productId != null) l.productId!
      ];
      if (ids.isEmpty) return 0;
      final stock =
          await ref.read(warehousesRepositoryProvider).stockOf(whId);
      final avail = {
        for (final s in stock) s.productId: s.available
      };
      final products = await ref
          .read(productsRepositoryProvider)
          .getMany(ids);
      final byId = {for (final p in products) p.id: p};
      final repo = ref.read(shortagesRepositoryProvider);
      var count = 0;
      for (final l in _cart) {
        final pid = l.productId;
        if (pid == null) continue;
        final a = avail[pid] ?? 0;
        final p = byId[pid];
        final min = p?.minimumStock ?? 0;
        // الكمية الناقصة + تعويض الحد الأدنى بعد البيع.
        final need = l.qty - a + min;
        if (need > 0) {
          await repo.record(
            productId: pid,
            warehouseId: whId,
            supplierId: p?.supplierId,
            requiredQty: need,
            sourceType: 'SALES_INVOICE',
            sourceId: invoiceId,
          );
          count++;
        }
      }
      ref.invalidate(shortagesPendingCountProvider);
      return count;
    } catch (_) {
      return 0;
    }
  }

  List<ShortageLine> get _shortageLines => [
        for (final l in _cart)
          ShortageLine(
              productId: l.productId,
              name: l.name,
              qty: l.qty),
      ];

  /// سطور السلة المتجاوزة (المطلوب > المتاح) — مشترك مع شاشة التفاصيل.
  Future<List<ExceedingLine>> _exceedingLines() async {
    final whId = _warehouseId;
    if (whId == null) return [];
    final out =
        await findExceeding(ref.read, whId, _shortageLines);
    // حدث خريطة العرض مع الفحص.
    try {
      final avail = await fetchAvailability(ref.read, whId);
      if (mounted) setState(() => _avail = avail);
    } catch (_) {}
    return out;
  }

  /// حوار الناقص الموحد — يرجع true للمتابعة.
  Future<bool> _shortageDialog(
      List<ExceedingLine> exceeding) async {
    _autoRequestSupply = false;
    final choice =
        await showShortageDialog(context, exceeding);
    if (choice == ShortageChoice.cancel) return false;
    if (choice == ShortageChoice.adjust) {
      setState(() {
        for (final e in exceeding) {
          final i = _cart.indexWhere(
              (l) => l.productId == e.line.productId);
          if (i >= 0) _cart[i].qty = e.available;
        }
        _cart.removeWhere((l) => l.qty <= 0);
      });
      _autoRequestSupply = false;
    } else {
      _autoRequestSupply = true;
    }
    return true;
  }

  /// طلب توريد تلقائي بالناقص (مشترك) — بعد إنشاء الفاتورة.
  Future<int> _autoSupplyRequest(String invoiceId) {
    final whId = _warehouseId;
    if (whId == null) return Future.value(0);
    return autoSupplyRequest(ref.read,
        invoiceId: invoiceId,
        warehouseId: whId,
        lines: _shortageLines);
  }

  /// سؤال العربون المشترك — بعد الحفظ.
  Future<void> _depositPrompt(String invoiceId) =>
      depositPrompt(context, invoiceId);

  /// العربون يتسأل عنه فقط لو الدفع آجل (مش كاش)
  /// أو لو الفاتورة فيها صنف خاص (تصنيع).
  bool get _isCreditSelected {
    for (final m in _payMethods) {
      if ((m['id'] as String?) == _paymentId) {
        return ((m['code'] as String?)?.toUpperCase() ==
            'CREDIT');
      }
    }
    return false;
  }

  bool get _shouldAskDeposit =>
      _isCreditSelected ||
      _cart.any((l) => l.isCustom);

  /// Saves the draft then submits it for approval using the
  /// existing repository calls (same flow as detail screen).
  Future<void> _saveAndSubmit() async {
    if (_cart.isEmpty || _warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('أكمل الأصناف والمخزن أولا.')));
      return;
    }
    if (_customerId == null && _walkIn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر عميلا أو أدخل اسم العميل النقدي.')));
      return;
    }
    final shipErr = _shippingError();
    if (shipErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(shipErr)));
      return;
    }
    // فحص المتاح قبل الحفظ (نفس دورة المسودة).
    final exceeding = await _exceedingLines();
    if (exceeding.isNotEmpty && mounted) {
      final ok = await _shortageDialog(exceeding);
      if (!ok || !mounted) return;
      if (_cart.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('السلة فارغة بعد التقليل للمتاح.')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final id = await repo.createDraft(
        customerId: _customerId,
        customerName:
            _customerId == null ? _walkIn.text.trim() : null,
        warehouseId: _warehouseId,
        paymentMethodId: _paymentId,
        reference: _ref.text,
        delivery: _delivery,
        creditReason: _creditReason.text,
        items: [
          for (final l in _cart)
            SalesItemInput(
              productId: l.productId,
              itemName: l.name,
              sku: l.sku,
              quantity: l.qty,
              unitPrice: l.price,
              unitCost: l.cost,
              serialNumbers: l.serials,
              taxRate: l.taxRate,
              itemType: l.isCustom ? 'CUSTOMIZED' : 'STANDARD',
              customUnit: l.customUnit,
              lengthValue: l.lengthValue,
              lengthUnit: l.lengthUnit,
              widthValue: l.widthValue,
              widthUnit: l.widthUnit,
              rawMaterialId: l.rawMaterialId,
              rawMaterialName: l.rawMaterialName,
              qtyPerRoll: l.qtyPerRoll,
              customNotes: l.customNotes,
            ),
        ],
      );
      await repo.submit(id);
      ref.invalidate(salesPageProvider);
      final shortages = await _checkShortages(id);
      var supplied = 0;
      if (_autoRequestSupply) {
        supplied = await _autoSupplyRequest(id);
      }
      _autoRequestSupply = false;
      if (_needsShipping) {
        await _autoCreateShipment(id);
      }
      // الأصناف الخاصة → طلبات تصنيع تلقائية.
      final mfgCount =
          await ensureCustomizedForInvoice(ref, id);
      if (mounted) {
        final msgs = <String>[];
        if (shortages > 0) {
          msgs.add(
              'واتسجل $shortages صنف في النواقص لعدم كفاية الرصيد');
        }
        if (supplied > 0) {
          msgs.add(
              'واتعمل $supplied طلب توريد بالناقص وراح لاعتماد المدير');
        }
        if (mfgCount > 0) {
          msgs.add(
              'واتنشأ $mfgCount طلب تصنيع للأصناف الخاصة');
        }
        if (msgs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'تم الإرسال للاعتماد، ${msgs.join('، ')}.')));
        }
        // العربون للآجل أو الصنف الخاص فقط — مش للكاش.
        if (_shouldAskDeposit) {
          await _depositPrompt(id);
        } else {
          context.pushReplacement('/sales/$id');
        }
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

  /// حفظ مباشر (نسخة الجهاز فقط — مستخدم واحد):
  /// إنشاء + اعتماد + خصم المخزون فورا بدون مركز موافقات.
  /// الشحن: تتعمل شحنة وتتشحن تلقائيا (الخصم يتم عند الشحن).
  /// الاستلام الفوري: خصم مباشر من المخزن.
  Future<void> _saveDirect() async {
    if (_cart.isEmpty || _warehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('أكمل الأصناف والمخزن أولا.')));
      return;
    }
    if (_customerId == null && _walkIn.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('اختر عميلا أو أدخل اسم العميل النقدي.')));
      return;
    }
    final shipErr = _shippingError();
    if (shipErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(shipErr)));
      return;
    }
    final exceeding = await _exceedingLines();
    if (exceeding.isNotEmpty && mounted) {
      final ok = await _shortageDialog(exceeding);
      if (!ok || !mounted) return;
      if (_cart.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('السلة فارغة بعد التقليل للمتاح.')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final id = await repo.createAndApprove(
        customerId: _customerId,
        customerName:
            _customerId == null ? _walkIn.text.trim() : null,
        warehouseId: _warehouseId,
        paymentMethodId: _paymentId,
        reference: _ref.text,
        delivery: _delivery,
        creditReason: _creditReason.text,
        items: [
          for (final l in _cart)
            SalesItemInput(
              productId: l.productId,
              itemName: l.name,
              sku: l.sku,
              quantity: l.qty,
              unitPrice: l.price,
              unitCost: l.cost,
              serialNumbers: l.serials,
              taxRate: l.taxRate,
              itemType: l.isCustom ? 'CUSTOMIZED' : 'STANDARD',
              customUnit: l.customUnit,
              lengthValue: l.lengthValue,
              lengthUnit: l.lengthUnit,
              widthValue: l.widthValue,
              widthUnit: l.widthUnit,
              rawMaterialId: l.rawMaterialId,
              rawMaterialName: l.rawMaterialName,
              qtyPerRoll: l.qtyPerRoll,
              customNotes: l.customNotes,
            ),
        ],
      );
      ref.invalidate(salesPageProvider);
      final shortages = await _checkShortages(id);
      // نسخة الجهاز: لا توريد تلقائي (الوحدة خارج النطاق)
      // ولا أوامر تصنيع — الفاتورة معتمدة ومخصومة فورا.
      _autoRequestSupply = false;
      if (_needsShipping) {
        await _autoCreateAndShip(id);
      }
      if (mounted) {
        if (shortages > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'تم حفظ واعتماد الفاتورة وخصم المخزون، '
                  'واتسجل $shortages صنف في النواقص لعدم كفاية الرصيد.')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'تم حفظ واعتماد الفاتورة وخصم المخزون.')));
        }
        if (_shouldAskDeposit) {
          await _depositPrompt(id);
        } else {
          context.pushReplacement('/sales/$id');
        }
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

  /// إنشاء شحنة مربوطة بالفاتورة وشحنها فورا (نسخة الجهاز):
  /// الخصم من المخزن يتم عند الشحن.
  Future<void> _autoCreateAndShip(String invoiceId) async {
    try {
      final shipRepo = ref.read(shippingRepositoryProvider);
      final shipId = await shipRepo.create({
        'sales_invoice_id': invoiceId,
        'customer_id': _customerId,
        'shipping_company':
            _shipCompany.text.trim().isEmpty
                ? null
                : _shipCompany.text.trim(),
        'recipient_name': _shipName.text.trim(),
        'recipient_phone': _shipPhone.text.trim(),
        'address': _shipAddress.text.trim(),
        'city': _shipCity.text.trim().isEmpty
            ? null
            : _shipCity.text.trim(),
        'shipping_cost':
            double.tryParse(_shipCost.text.trim()) ?? 0,
        'delivery_method': 'SHIPPING',
        'status': 'PREPARING',
      });
      ref.invalidate(shipmentsPageProvider);
      await shipRepo.ship(shipId);
      ref.invalidate(shipmentsPageProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? 'الفاتورة اعتمدت بس الشحن/الخصم مكملش: ${e.messageAr} — اشحنها من شاشة الشحن.'
              : 'الفاتورة اعتمدت بس الشحن مكملش — اشحنها من شاشة الشحن.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsSection = _ItemsSection(
      cart: _cart,
      avail: _avail,
      onScan: _scan,
      onSearch: _manualSearch,
      onCustom: _addCustom,
      onDec: _dec,
      onInc: _inc,
      onRemove: _remove,
      onPrice: _setPrice,
      onSerials: _pickSerials,
      hasTax: _hasTax,
      onTaxToggle: _onTaxToggle,
      globalTaxCtrl: _globalTaxCtrl,
      onGlobalTaxChanged: _onGlobalTaxChanged,
    );
    final sideSection = _SideSection(
      customerName: _customerName,
      customerId: _customerId,
      onPickCustomer: _pickCustomer,
      walkIn: _walkIn,
      warehouseId: _warehouseId,
      warehouses: _warehouses,
      onWarehouse: (v) {
        setState(() => _warehouseId = v);
        _refreshAvail();
      },
      paymentId: _paymentId,
      payMethods: _payMethods,
      onPayment: (v) => setState(() => _paymentId = v),
      ref: _ref,
      delivery: _delivery,
      onDelivery: (v) =>
          setState(() => _delivery = v ?? 'OFFICE_PICKUP'),
      creditReason: _creditReason,
      shipCompany: _shipCompany,
      shipName: _shipName,
      shipPhone: _shipPhone,
      shipAddress: _shipAddress,
      shipCity: _shipCity,
      shipCost: _shipCost,
      subtotal: _subtotal,
      taxTotal: _taxTotal,
      grandTotal: _grandTotal,
      hasTax: _hasTax,
      saving: _saving,
      onSave: _save,
      onSubmit: _saveAndSubmit,
      isLocal: resolveBackendMode() == BackendMode.local,
      onSaveDirect: _saveDirect,
    );

    return ResponsiveLayout(
      mobile: Form(
        key: _form,
        child: context.isDesktop
            ? Padding(
                padding: EdgeInsets.all(
                    context.contentPadding),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 3, child: itemsSection),
                    const SizedBox(
                        width: AppSpacing.mdx),
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                          child: sideSection),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: EdgeInsets.all(
                    context.contentPadding),
                children: [
                  _FormSteps(done: [
                    (_customerId != null ||
                            _walkIn.text.trim().isNotEmpty) &&
                        _warehouseId != null,
                    _cart.isNotEmpty,
                    _paymentId != null,
                  ]),
                  const SizedBox(height: AppSpacing.mdx),
                  sideSection,
                  const SizedBox(
                      height: AppSpacing.mdx),
                  itemsSection,
                ],
              ),
      ),
    );
  }
}

class _SideSection extends StatelessWidget {
  final String? customerName;
  final String? customerId;
  final VoidCallback onPickCustomer;
  final TextEditingController walkIn;
  final String? warehouseId;
  final List<dynamic> warehouses;
  final ValueChanged<String?> onWarehouse;
  final String? paymentId;
  final List<dynamic> payMethods;
  final ValueChanged<String?> onPayment;
  final TextEditingController ref;
  final String delivery;
  final ValueChanged<String?> onDelivery;
  final TextEditingController creditReason;
  final TextEditingController shipCompany;
  final TextEditingController shipName;
  final TextEditingController shipPhone;
  final TextEditingController shipAddress;
  final TextEditingController shipCity;
  final TextEditingController shipCost;
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final bool hasTax;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onSubmit;
  // نسخة الجهاز: زرار واحد للحفظ المباشر (بدون موافقات).
  final bool isLocal;
  final VoidCallback onSaveDirect;
  const _SideSection({
    required this.customerName,
    required this.customerId,
    required this.onPickCustomer,
    required this.walkIn,
    required this.warehouseId,
    required this.warehouses,
    required this.onWarehouse,
    required this.paymentId,
    required this.payMethods,
    required this.onPayment,
    required this.ref,
    required this.delivery,
    required this.onDelivery,
    required this.creditReason,
    required this.shipCompany,
    required this.shipName,
    required this.shipPhone,
    required this.shipAddress,
    required this.shipCity,
    required this.shipCost,
    required this.subtotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.hasTax,
    required this.saving,
    required this.onSave,
    required this.onSubmit,
    this.isLocal = false,
    required this.onSaveDirect,
  });

  @override
  Widget build(BuildContext context) {
    // كود طريقة الدفع المختارة لتحديد سلوك المستحقات:
    // غير آجل = مدفوع بالكامل ولا يظهر في المستحقات، آجل = المتبقي مستحق.
    String? selectedCode;
    for (final m in payMethods) {
      if ((m['id'] as String?) == paymentId) {
        selectedCode = (m['code'] as String?)?.toUpperCase();
        break;
      }
    }
    final isCredit = selectedCode == 'CREDIT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'العميل والدفع'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(
                    Icons.person_outline,
                    size: 20),
                title: Text(
                    customerName ?? 'اختيار العميل'),
                subtitle: customerId == null
                    ? const Text(
                        'أو أدخل عميل نقدي بالأسفل')
                    : null,
                trailing: TextButton(
                    onPressed: onPickCustomer,
                    child: const Text('اختيار')),
              ),
              if (customerId == null)
                TextField(
                    controller: walkIn,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'اسم العميل النقدي *')),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: warehouseId,
                decoration: const InputDecoration(
                    labelText: 'المخزن *'),
                items: [
                  for (final w in warehouses)
                    DropdownMenuItem(
                        value: w.id,
                        child: Text(
                            '${w.name} (${w.code})')),
                ],
                onChanged: onWarehouse,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: paymentId,
                decoration: const InputDecoration(
                    labelText: 'طريقة الدفع'),
                items: [
                  for (final m in payMethods)
                    DropdownMenuItem(
                        value: m['id'] as String,
                        child: Text((m['name_ar'] ??
                                m['code'])
                            .toString())),
                ],
                onChanged: onPayment,
              ),
              const SizedBox(height: AppSpacing.sm),
              // توضيح سلوك المستحقات حسب طريقة الدفع.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCredit
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isCredit
                      ? 'آجل: سجل سبب الآجل. لو الزبون دفع عربون سجله من (تسجيل دفعة) بعد الاعتماد، والباقي هينزل عليه في المستحقات.'
                      : 'مدفوع (${selectedCode ?? '—'}): الزبون دفع خلاص، الفاتورة مش هتنزل عليه في المستحقات بعد الاعتماد.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCredit
                        ? Colors.orange.shade900
                        : Colors.green.shade900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                  controller: ref,
                  decoration:
                      const InputDecoration(
                          labelText:
                              'رقم مرجعي (اختياري)')),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: delivery,
                decoration: const InputDecoration(
                    labelText: 'التوصيل'),
                items: const [
                  DropdownMenuItem(
                      value: 'OFFICE_PICKUP',
                      child:
                          Text('استلام من الفرع')),
                  DropdownMenuItem(
                      value: 'SHIPPING',
                      child: Text('شحن')),
                ],
                onChanged: onDelivery,
              ),
              if (delivery == 'SHIPPING') ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: Text(
                    'شحن: املأ بيانات التوصيل وهتتعمل شحنة مربوطة بالفاتورة تلقائيا بعد الحفظ.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipCompany,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'شركة الشحن (اختياري)')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipName,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'اسم المستلم *')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipPhone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'هاتف المستلم *')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipAddress,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'العنوان *')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipCity,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'المدينة (اختياري)')),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                    controller: shipCost,
                    keyboardType: const TextInputType
                        .numberWithOptions(
                            decimal: true),
                    textDirection:
                        TextDirection.ltr,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'تكلفة الشحن (اختياري)')),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (isCredit)
                TextField(
                    controller: creditReason,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سبب الآجل * (إجباري للبيع الآجل)')),
              if (!isCredit)
                TextField(
                    controller: creditReason,
                    decoration:
                        const InputDecoration(
                            labelText:
                                'سبب الآجل (للبيع الآجل فقط)')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              _TotalHero(
                subtotal: subtotal,
                taxTotal: taxTotal,
                grandTotal: grandTotal,
                hasTax: hasTax,
              ),
              const SizedBox(height: AppSpacing.md),
              if (isLocal) ...[
                FilledButton.icon(
                  onPressed: saving ? null : onSaveDirect,
                  icon: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child:
                              CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                      : const Icon(
                          Icons.check_circle_outline,
                          size: 20),
                  label: const Text(
                      'حفظ الفاتورة (اعتماد وخصم فوري)'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'نسخة الجهاز: الحفظ يعتمد الفاتورة ويخصم المخزون فورا بدون موافقات.',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                FilledButton(
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child:
                              CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                      : const Text('حفظ كمسودة'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: saving ? null : onSubmit,
                  child:
                      const Text('حفظ وإرسال للموافقة'),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// بطاقة الإجمالي الداكنة (إجمالي الأصناف + الضريبة + إجمالي الفاتورة).
class _TotalHero extends StatelessWidget {
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final bool hasTax;
  const _TotalHero({
    required this.subtotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.hasTax,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: AppColors.heroSoft)),
              Text(v,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: AppColors.heroSoft)),
            ],
          ),
        );
    return YadHeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          row('إجمالي الأصناف', AppFormat.money(subtotal, suffix: '')),
          row('الضريبة',
              hasTax ? AppFormat.money(taxTotal, suffix: '') : 'بدون ضريبة'),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: .18))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('إجمالي الفاتورة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(AppFormat.money(grandTotal, suffix: ''),
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(width: 4),
                    const Text('ج.م',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.heroSoft)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// مؤشر خطوات الفاتورة: 1 البيانات · 2 الأصناف · 3 الدفع.
/// الشريط يمتلئ (900ms) كلما اكتملت الخطوة.
class _FormSteps extends StatelessWidget {
  final List<bool> done;
  const _FormSteps({required this.done});

  static const _labels = ['1. البيانات', '2. الأصناف', '3. الدفع'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? AppColors.darkDivider
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: AlignmentDirectional.centerStart,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: done[i] ? 1 : 0),
                    duration: yadDuration(context, 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        decoration: const BoxDecoration(
                            gradient: AppColors.actionGradient),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(_labels[i],
                    style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight:
                            done[i] ? FontWeight.w700 : FontWeight.w600,
                        color: done[i]
                            ? AppColors.indigoDeep
                            : AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SummaryRow(
      {required this.label,
      required this.value,
      this.bold = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: bold
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium)),
          Text(value,
              style: bold
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  final List<_CartLine> cart;
  final Map<String, double> avail;
  final VoidCallback onScan;
  final VoidCallback onSearch;
  final VoidCallback onCustom;
  final ValueChanged<int> onDec;
  final ValueChanged<int> onInc;
  final ValueChanged<int> onRemove;
  final void Function(int, double) onPrice;
  final ValueChanged<int> onSerials;
  final bool hasTax;
  final ValueChanged<bool?> onTaxToggle;
  final TextEditingController globalTaxCtrl;
  final ValueChanged<String> onGlobalTaxChanged;
  const _ItemsSection({
    required this.cart,
    required this.avail,
    required this.onScan,
    required this.onSearch,
    required this.onCustom,
    required this.onDec,
    required this.onInc,
    required this.onRemove,
    required this.onPrice,
    required this.onSerials,
    required this.hasTax,
    required this.onTaxToggle,
    required this.globalTaxCtrl,
    required this.onGlobalTaxChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment:
                  WrapCrossAlignment.center,
              children: [
                Text('الأصناف (${cart.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium),
                const SizedBox(width: 8),
                TextButton.icon(
                    onPressed: onScan,
                    icon: const Icon(
                        Icons.barcode_reader,
                        size: 18),
                    label: const Text('مسح')),
                TextButton.icon(
                    onPressed: onSearch,
                    icon: const Icon(
                        Icons.search_outlined,
                        size: 18),
                    label: const Text('بحث')),
                TextButton.icon(
                    onPressed: onCustom,
                    icon: const Icon(
                        Icons.handyman_outlined,
                        size: 18),
                    label: const Text('+ صنف خاص')),
              ],
            ),
          ),
          if (cart.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.mdx),
              child: EmptyState(
                icon: Icons.shopping_basket_outlined,
                title: 'لا توجد أصناف بعد',
                subtitle:
                    'امسح باركود أو ابحث لإضافة الأصناف',
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md),
              child: Column(
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('يوجد ضريبة؟'),
                    value: hasTax,
                    onChanged: onTaxToggle,
                  ),
                  if (hasTax)
                    TextField(
                      controller: globalTaxCtrl,
                      keyboardType: const TextInputType
                          .numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'نسبة الضريبة % (تطبق على كل الأصناف)',
                        isDense: true,
                      ),
                      onChanged: onGlobalTaxChanged,
                    ),
                ],
              ),
            ),
            if (context.isDesktop)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle:
                      Theme.of(context)
                          .textTheme
                          .labelMedium,
                  dataTextStyle:
                      Theme.of(context)
                          .textTheme
                          .bodyMedium,
                  headingRowHeight: 36,
                  dataRowMinHeight: 44,
                  columns: const [
                    DataColumn(label: Text('الصنف')),
                    DataColumn(
                        label: Text('الكمية'),
                        numeric: true),
                    DataColumn(
                        label: Text('السعر'),
                        numeric: true),
                    DataColumn(
                        label: Text('الإجمالي'),
                        numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (var i = 0;
                        i < cart.length;
                        i++)
                      DataRow(cells: [
                        DataCell(Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${cart[i].isCustom ? '🔧 ' : ''}${cart[i].name}'),
                            if (cart[i].productId != null)
                              _AvailText(
                                qty: cart[i].qty,
                                available: avail[
                                    cart[i].productId],
                              ),
                            if (cart[i].isElectronics)
                              _SerialText(
                                serials:
                                    cart[i].serials,
                                qty: cart[i].qty,
                                onPick: () =>
                                    onSerials(i),
                              ),
                            if (cart[i].isCustom &&
                                cart[i]
                                    .specSummary
                                    .isNotEmpty)
                              Text(
                                cart[i].specSummary,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color:
                                            Colors.grey),
                              ),
                          ],
                        )),
                        DataCell(Text('${cart[i].qty}')),
                        DataCell(
                          SizedBox(
                            width: 90,
                            child: TextFormField(
                              key: ValueKey(
                                  'price-desktop-$i'),
                              initialValue:
                                  cart[i].price.toString(),
                              keyboardType:
                                  const TextInputType
                                      .numberWithOptions(
                                      decimal: true),
                              textDirection:
                                  TextDirection.ltr,
                              decoration:
                                  const InputDecoration(
                                labelText: 'سعر البيع',
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8),
                              ),
                              onChanged: (v) {
                                final d =
                                    double.tryParse(v);
                                if (d != null && d >= 0) {
                                  onPrice(i, d);
                                }
                              },
                            ),
                          ),
                        ),
                        DataCell(Text((cart[i].qty *
                                cart[i].price)
                            .toStringAsFixed(2))),
                        DataCell(Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            if (cart[i]
                                .isElectronics)
                              IconButton(
                                  iconSize: 18,
                                  tooltip:
                                      'سيريالات العميل',
                                  icon: const Icon(Icons
                                      .barcode_reader),
                                  onPressed: () =>
                                      onSerials(i)),
                            IconButton(
                                iconSize: 18,
                                icon: const Icon(Icons
                                    .remove_outlined),
                                onPressed: () =>
                                    onDec(i)),
                            IconButton(
                                iconSize: 18,
                                icon: const Icon(Icons
                                    .add_outlined),
                                onPressed: () =>
                                    onInc(i)),
                            IconButton(
                                iconSize: 18,
                                icon: const Icon(Icons
                                    .delete_outline),
                                onPressed: () =>
                                    onRemove(i)),
                          ],
                        )),
                      ]),
                  ],
                ),
              )
            else
              for (int i = 0; i < cart.length; i++)
                _CartTile(
                  key: ValueKey('cart-tile-$i'),
                  line: cart[i],
                  available: cart[i].productId == null
                      ? null
                      : avail[cart[i].productId],
                  onDec: () => onDec(i),
                  onInc: () => onInc(i),
                  onRemove: () => onRemove(i),
                  onPrice: (v) => onPrice(i, v),
                  onSerials: () => onSerials(i),
                ),
          ],
        ],
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  final _CartLine line;
  final double? available;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onRemove;
  final ValueChanged<double> onPrice;
  final VoidCallback onSerials;
  const _CartTile({
    super.key,
    required this.line,
    this.available,
    required this.onDec,
    required this.onInc,
    required this.onRemove,
    required this.onPrice,
    required this.onSerials,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(line.name,
                        style:
                            theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis),
                    Text(
                      '${line.isCustom ? '🔧 ' : ''}${line.qty} × ${AppFormat.money(line.price)} = ${AppFormat.money(line.qty * line.price)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (line.productId != null)
                      _AvailText(
                        qty: line.qty,
                        available: available,
                      ),
                    if (line.isElectronics)
                      _SerialText(
                        serials: line.serials,
                        qty: line.qty,
                        onPick: onSerials,
                      ),
                    if (line.isCustom &&
                        line.specSummary.isNotEmpty)
                      Text(
                        line.specSummary,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                                color: Colors.grey),
                      ),
                  ],
                ),
              ),
              IconButton(
                  iconSize: 20,
                  icon: const Icon(
                      Icons.remove_outlined),
                  onPressed: onDec),
              Text('${line.qty}',
                  style:
                      theme.textTheme.titleSmall),
              IconButton(
                  iconSize: 20,
                  icon:
                      const Icon(Icons.add_outlined),
                  onPressed: onInc),
              IconButton(
                  iconSize: 20,
                  icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger),
                  onPressed: onRemove),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey(
                'cart-price-${line.productId ?? line.name}'),
            initialValue: line.price.toString(),
            keyboardType: const TextInputType
                .numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'سعر البيع',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
            ),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null && d >= 0) {
                onPrice(d);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// سطر المتاح في المخزن تحت كل صنف في السلة.
/// أخضر لو الكمية متوفرة، وتحذير برتقالي لو المطلوب أكبر من المتاح.
/// (عرض فقط — الخصم الفعلي لا يتم إلا عند اعتماد المدير).
class _AvailText extends StatelessWidget {
  final double qty;
  final double? available;
  const _AvailText({required this.qty, this.available});

  static String _f(double v) =>
      v == v.truncateToDouble() ? v.truncate().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    if (available == null) {
      return Text(
        'المتاح: جاري التحميل…',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey, fontSize: 11),
      );
    }
    final ok = qty <= available!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!ok)
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 1),
            child: Icon(Icons.warning_amber_outlined,
                size: 14, color: Colors.deepOrange),
          ),
        Flexible(
          child: Text(
            'المتاح: ${_f(available!)}'
            '${ok ? '' : ' — المطلوب أكبر من المتاح!'}',
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ok ? Colors.green.shade700 : Colors.deepOrange,
                fontSize: 11,
                fontWeight:
                    ok ? FontWeight.normal : FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// سطر سيريالات العميل تحت الصنف الإلكتروني في السلة.
/// يعرض المختار (n/الكمية) مع زرار الاختيار من المخزون.
class _SerialText extends StatelessWidget {
  final List<String> serials;
  final double qty;
  final VoidCallback onPick;
  const _SerialText({
    required this.serials,
    required this.qty,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final need = qty.toInt();
    final done = serials.length >= need && need > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.verified_outlined
              : Icons.barcode_reader,
          size: 14,
          color: done ? Colors.green.shade700 : Colors.blue,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            serials.isEmpty
                ? 'سيريال العميل: اختار ($need)'
                : 'سيريال: ${serials.join(', ')} (${serials.length}/$need)',
            softWrap: true,
            textDirection: TextDirection.ltr,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: done
                        ? Colors.green.shade700
                        : Colors.blue.shade900,
                    fontSize: 11,
                    fontWeight: done
                        ? FontWeight.normal
                        : FontWeight.bold),
          ),
        ),
        TextButton(
          onPressed: onPick,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(
                horizontal: 8),
          ),
          child: const Text('اختيار',
              style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
