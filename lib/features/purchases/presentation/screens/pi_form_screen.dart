import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend/backend_mode.dart';
import '../../../../core/errors/failures.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../../products/presentation/providers/products_providers.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';
import '../../../suppliers/data/suppliers_repository.dart';
import '../../../suppliers/domain/supplier.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/purchases_repository.dart';
import '../../domain/purchases.dart';
import '../providers/purchases_providers.dart';

class _PIline {
  final String? productId;
  final String name;
  final String? sku;
  double qty;
  double cost;
  _PIline(
      {this.productId,
      required this.name,
      this.sku,
      required this.qty,
      required this.cost});
}

class PurchaseInvoiceFormScreen extends ConsumerStatefulWidget {
  const PurchaseInvoiceFormScreen({super.key});
  @override
  ConsumerState<PurchaseInvoiceFormScreen> createState() =>
      _PurchaseInvoiceFormScreenState();
}

class _PurchaseInvoiceFormScreenState
    extends ConsumerState<PurchaseInvoiceFormScreen> {
  final _ref = TextEditingController();
  final _supplierCtrl = TextEditingController();
  // اسم المورد النقدي (بديل اختيار مورد مسجل) — يظهر عند عدم الاختيار.
  final _cashSupplierCtrl = TextEditingController();
  final _supplierFocus = FocusNode();
  final _productCtrl = TextEditingController();
  final _productFocus = FocusNode();
  final _invoiceTax = TextEditingController(text: '14');
  String? _supplierId;
  String? _supplierName;
  String? _warehouseId;
  String? _paymentId;
  List<Warehouse> _warehouses = [];
  List<Map<String, dynamic>> _payMethods = [];
  final _lines = <_PIline>[];
  List<Supplier> _supOptions = [];
  List<Product> _prodOptions = [];
  bool _supLoading = false;
  bool _prodLoading = false;
  bool _hasTax = false;
  Timer? _debSupplier;
  Timer? _debProduct;
  // إخفاء مؤجل لقوائم الاقتراحات: الضغطة على "إضافة" بتسحب
  // الفوكس من حقل البحث، ولو أخفينا القائمة فورا الضغطة
  // بتتبلع والصنف مش بيتضاف (خصوصا بالماوس على الديسكتوب).
  Timer? _hideSupOpts;
  Timer? _hideProdOpts;
  bool _saving = false;

  /// السكانر (كاميرا) شغال على الموبايل فقط — على الديسكتوب
  /// مكتبة mobile_scanner ملهاش تنفيذ وبتطلع MissingPluginException.
  bool get _canScan {
    try {
      if (kIsWeb) return false;
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _supplierFocus.addListener(() {
      if (_supplierFocus.hasFocus) {
        _hideSupOpts?.cancel();
      } else {
        _hideSupOpts?.cancel();
        _hideSupOpts = Timer(
            const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _supOptions = []);
        });
      }
    });
    _productFocus.addListener(() {
      if (_productFocus.hasFocus) {
        _hideProdOpts?.cancel();
      } else {
        _hideProdOpts?.cancel();
        _hideProdOpts = Timer(
            const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _prodOptions = []);
        });
      }
    });
    Future.microtask(_preload);
  }

  Future<void> _preload() async {
    try {
      final wh = await ref
          .read(warehousesRepositoryProvider)
          .list(onlyActive: true);
      final pm =
          await ref.read(purchasesRepositoryProvider).paymentMethods();
      if (!mounted) return;
      setState(() {
        _warehouses = wh;
        _payMethods = pm;
        // المخزن إجباري باختيار صريح من المستخدم — مفيش
        // اختيار تلقائي عشان الكمية متنزلش في مخزن غلط.
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _debSupplier?.cancel();
    _debProduct?.cancel();
    _hideSupOpts?.cancel();
    _hideProdOpts?.cancel();
    _ref.dispose();
    _supplierCtrl.dispose();
    _cashSupplierCtrl.dispose();
    _supplierFocus.dispose();
    _productCtrl.dispose();
    _productFocus.dispose();
    _invoiceTax.dispose();
    super.dispose();
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  String _err(Object e) =>
      e is AppFailure ? e.messageAr : 'حدث خطأ أثناء تنفيذ العملية.';

  double get _taxRate =>
      _hasTax ? (double.tryParse(_invoiceTax.text.trim()) ?? 0) : 0;

  double get _subtotal =>
      _lines.fold(0, (s, l) => s + l.qty * l.cost);

  double get _taxAmount => _subtotal * _taxRate / 100;

  double get _grandTotal => _subtotal + _taxAmount;

  // ---------- المورد: اقتراحات أثناء الكتابة ----------
  void _onSupplierChanged(String v) {
    _debSupplier?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _supOptions = [];
        _supplierId = null;
        _supplierName = null;
      });
      return;
    }
    // لو اختار من الاقتراحات ولسه نفس الاسم، لا تبحث تاني.
    if (v.trim() == (_supplierName ?? '')) return;
    _supplierId = null;
    _supplierName = null;
    _debSupplier = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _supLoading = true);
      try {
        final r = await ref
            .read(suppliersRepositoryProvider)
            .search(query: v, pageSize: 10);
        if (!mounted) return;
        setState(() {
          _supOptions = r;
          _supLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _supLoading = false);
      }
    });
  }

  void _pickSupplier(Supplier s) {
    _hideSupOpts?.cancel();
    setState(() {
      _supplierId = s.id;
      _supplierName = s.name;
      _supplierCtrl.text = s.name;
      _cashSupplierCtrl.clear();
      _supOptions = [];
    });
    _supplierFocus.unfocus();
  }

  /// true لو تم تحديد طرف الفاتورة (مورد مسجل أو اسم نقدي).
  bool get _hasParty =>
      _supplierId != null || _cashSupplierCtrl.text.trim().isNotEmpty;

  // ---------- الصنف: اقتراحات + مسح باركود ----------
  void _onProductChanged(String v) {
    _debProduct?.cancel();
    _hideProdOpts?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _prodOptions = []);
      return;
    }
    _debProduct = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _prodLoading = true);
      try {
        final r = await ref
            .read(productsRepositoryProvider)
            .search(query: v, pageSize: 10);
        if (!mounted) return;
        setState(() {
          _prodOptions = r;
          _prodLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _prodLoading = false);
        _msg(_err(e));
      }
    });
  }

  /// دمج سطر في الفاتورة — آخر سعر شراء مدخل هو المعتمد.
  void _mergeLine(Product p,
      {required double qty, required double cost}) {
    _hideProdOpts?.cancel();
    setState(() {
      final i = _lines.indexWhere(
          (l) => l.productId != null && l.productId == p.id);
      if (i >= 0) {
        _lines[i].qty += qty;
        _lines[i].cost = cost;
      } else {
        _lines.add(_PIline(
            productId: p.id,
            name: p.name,
            sku: p.sku,
            qty: qty,
            cost: cost));
      }
      _prodOptions = [];
      _productCtrl.clear();
    });
    _productFocus.unfocus();
  }

  /// رقم بدون أصفار زائدة لحقل السعر (50.0 → 50).
  String _numStr(double v) {
    var s = v.toString();
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// شيت الكمية وسعر الشراء — يظهر فور اختيار الصنف من
  /// البحث أو السكانر، والسعر الافتراضي هو آخر سعر مسجل.
  Future<void> _addProductSheet(Product p) async {
    _hideProdOpts?.cancel();
    setState(() => _prodOptions = []);
    _productFocus.unfocus();
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl =
        TextEditingController(text: _numStr(p.purchasePrice));
    try {
      final res = await showModalBottomSheet<
          ({double qty, double cost})>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Text(
                p.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'آخر سعر شراء مسجل: ${p.purchasePrice}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'الكمية *',
                  prefixIcon:
                      Icon(Icons.numbers_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText:
                      'سعر الشراء من المورد *',
                  prefixIcon:
                      Icon(Icons.payments_outlined),
                  helperText:
                      'هيتحدث في بطاقة الصنف عند حفظ الفاتورة',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final q = double.tryParse(
                      qtyCtrl.text.trim());
                  final c = double.tryParse(
                      costCtrl.text.trim());
                  if (q == null || q <= 0) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(
                      const SnackBar(
                          content: Text(
                              'ادخل كمية أكبر من صفر.')),
                    );
                    return;
                  }
                  if (c == null || c < 0) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(
                      const SnackBar(
                          content: Text(
                              'ادخل سعر شراء صحيح.')),
                    );
                    return;
                  }
                  Navigator.of(ctx)
                      .pop((qty: q, cost: c));
                },
                child: const Text('إضافة للفاتورة'),
              ),
            ],
          ),
        ),
      );
      if (res == null || !mounted) return;
      _mergeLine(p, qty: res.qty, cost: res.cost);
    } finally {
      qtyCtrl.dispose();
      costCtrl.dispose();
    }
  }

  Future<void> _scanProduct() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final p = await ref
          .read(productsRepositoryProvider)
          .findByBarcode(code);
      if (!mounted) return;
      if (p == null) {
        _msg('لم يتم العثور على صنف بهذا الباركود');
        return;
      }
      await _addProductSheet(p);
    } catch (e) {
      if (!mounted) return;
      _msg(_err(e));
    }
  }

  Future<void> _save() async {
    if (!_hasParty) {
      _msg('اختار المورد من الاقتراحات أو أدخل اسم المورد النقدي.');
      return;
    }
    if (_warehouseId == null) {
      _msg('اختار المخزن اللي هتنزل فيه الكمية أولا.');
      return;
    }
    if (_lines.isEmpty) {
      _msg('أضف صنفا واحدا على الأقل.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(purchasesRepositoryProvider).createInvoice(
            supplierId: _supplierId,
            supplierName:
                _supplierId == null ? _cashSupplierCtrl.text : null,
            warehouseId: _warehouseId,
            paymentMethodId: _paymentId,
            reference: _ref.text,
            items: [
              for (final l in _lines)
                PIItemInput(
                    productId: l.productId,
                    productName: l.name,
                    sku: l.sku,
                    quantity: l.qty,
                    unitCost: l.cost,
                    taxRate: _taxRate),
            ],
          );
      // سعر الشراء المدخل يتحدث في بطاقة الصنف — أفضل جهد:
      // فشل التحديث (مثلا صلاحيات) لا يلغي الفاتورة المحفوظة.
      var priceSyncFailed = 0;
      for (final l in _lines) {
        if (l.productId == null) continue;
        try {
          await ref
              .read(productsRepositoryProvider)
              .update(l.productId!, {'purchase_price': l.cost});
        } catch (_) {
          priceSyncFailed++;
        }
      }
      ref.invalidate(piPageProvider);
      ref.invalidate(productsPageProvider);
      if (!mounted) return;
      if (priceSyncFailed > 0) {
        _msg('اتحفظت الفاتورة، بس سعر الشراء متحدثش في '
            '$priceSyncFailed أصناف (راجع صلاحيات الأصناف).');
      }
      context.pushReplacement('/purchase-invoices/$id');
    } catch (e) {
      if (!mounted) return;
      _msg(_err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// حفظ مباشر (نسخة الجهاز فقط — مستخدم واحد):
  /// إنشاء + اعتماد + زيادة المخزون فورا بدون مركز موافقات.
  Future<void> _saveDirect() async {
    if (!_hasParty) {
      _msg('اختار المورد من الاقتراحات أو أدخل اسم المورد النقدي.');
      return;
    }
    if (_warehouseId == null) {
      _msg('اختار المخزن اللي هتنزل فيه الكمية أولا.');
      return;
    }
    if (_lines.isEmpty) {
      _msg('أضف صنفا واحدا على الأقل.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(purchasesRepositoryProvider).createAndApproveInvoice(
            supplierId: _supplierId,
            supplierName:
                _supplierId == null ? _cashSupplierCtrl.text : null,
            warehouseId: _warehouseId,
            paymentMethodId: _paymentId,
            reference: _ref.text,
            items: [
              for (final l in _lines)
                PIItemInput(
                    productId: l.productId,
                    productName: l.name,
                    sku: l.sku,
                    quantity: l.qty,
                    unitCost: l.cost,
                    taxRate: _taxRate),
            ],
          );
      var priceSyncFailed = 0;
      for (final l in _lines) {
        if (l.productId == null) continue;
        try {
          await ref
              .read(productsRepositoryProvider)
              .update(l.productId!, {'purchase_price': l.cost});
        } catch (_) {
          priceSyncFailed++;
        }
      }
      ref.invalidate(piPageProvider);
      ref.invalidate(productsPageProvider);
      if (!mounted) return;
      if (priceSyncFailed > 0) {
        _msg('اتحفظت واعتمدت الفاتورة ونزلت المخزون، بس سعر الشراء متحدثش في '
            '$priceSyncFailed أصناف (راجع صلاحيات الأصناف).');
      } else {
        _msg('تم حفظ واعتماد الفاتورة ونزول الكمية في المخزن.');
      }
      context.pushReplacement('/purchase-invoices/$id');
    } catch (e) {
      if (!mounted) return;
      _msg(_err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('فاتورة مشتريات جديدة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- المورد ----
          TextField(
            controller: _supplierCtrl,
            focusNode: _supplierFocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'المورد (اختياري — بحث في المسجلين)',
              hintText: 'اكتب حرف للبحث...',
              prefixIcon:
                  const Icon(Icons.handshake_outlined),
              suffixIcon: _supLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)),
                    )
                  : (_supplierCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_outlined),
                          onPressed: () {
                            _supplierCtrl.clear();
                            _onSupplierChanged('');
                          },
                        )
                      : null),
            ),
            onChanged: _onSupplierChanged,
          ),
          if (_supOptions.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in _supOptions)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                          Icons.handshake_outlined,
                          size: 20),
                      title: Text(s.name),
                      subtitle: s.phone == null
                          ? null
                          : Text(s.phone!,
                              textDirection:
                                  TextDirection.ltr),
                      onTap: () => _pickSupplier(s),
                    ),
                ],
              ),
            ),
          // مورد نقدي بالاسم (بديل اختيار مورد مسجل).
          if (_supplierId == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _cashSupplierCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم المورد النقدي (اختياري)',
                hintText: 'اكتب الاسم لو المورد مش مسجل...',
                prefixIcon:
                    Icon(Icons.person_outline),
                helperText:
                    'يكفي اختيار مورد مسجل أو كتابة اسم نقدي — واحد منهم',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _warehouseId,
            decoration: const InputDecoration(
              labelText: 'المخزن *',
              helperText:
                  'الكمية هتنزل في المخزن اللي تختاره',
            ),
            hint: const Text(
                'اختار المخزن اللي هتنزل فيه الكمية'),
            items: [
              for (final w in _warehouses)
                DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.name} (${w.code})')),
            ],
            onChanged: (v) =>
                setState(() => _warehouseId = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: _paymentId,
            decoration:
                const InputDecoration(labelText: 'طريقة الدفع'),
            items: [
              for (final m in _payMethods)
                DropdownMenuItem(
                    value: m['id'] as String,
                    child: Text(
                        (m['name_ar'] ?? m['code']).toString())),
            ],
            onChanged: (v) =>
                setState(() => _paymentId = v),
          ),
          Builder(builder: (context) {
            String? code;
            for (final m in _payMethods) {
              if ((m['id'] as String?) == _paymentId) {
                code = (m['code'] as String?)?.toUpperCase();
                break;
              }
            }
            final isCredit = code == 'CREDIT';
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCredit
                    ? Colors.orange.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isCredit
                    ? 'آجل: الباقي بعد الدفع هينزل في مستحقات المورد.'
                    : 'مدفوع (${code ?? '—'}): مش هينزل في المستحقات بعد الاعتماد.',
                style: TextStyle(
                  fontSize: 12,
                  color: isCredit
                      ? Colors.orange.shade900
                      : Colors.green.shade900,
                ),
                textAlign: TextAlign.center,
              ),
            );
          }),
          TextField(
              controller: _ref,
              decoration: const InputDecoration(
                  labelText: 'رقم مرجعي (اختياري)')),
          const Divider(height: 24),
          // ---- الصنف ----
          Row(children: [
            const Text('الأصناف',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_canScan)
              IconButton.filledTonal(
                tooltip: 'مسح باركود',
                icon: const Icon(Icons.barcode_reader),
                onPressed: _scanProduct,
              ),
          ]),
          TextField(
            controller: _productCtrl,
            focusNode: _productFocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'ابحث باسم الصنف أو SKU أو باركود',
              hintText: 'اكتب حرف للبحث...',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _prodLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: _onProductChanged,
          ),
          if (_prodOptions.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in _prodOptions)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                          Icons.inventory_2_outlined,
                          size: 20),
                      title: Text(p.name),
                      subtitle: Text(
                          '${p.sku} • شراء ${p.purchasePrice}',
                          textDirection:
                              TextDirection.ltr),
                      trailing: TextButton(
                        child: const Text('إضافة'),
                        onPressed: () =>
                            _addProductSheet(p),
                      ),
                      onTap: () => _addProductSheet(p),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (int i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(_lines[i].name),
                      subtitle: Text(
                          '${_lines[i].qty} × ${_lines[i].cost}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(
                                  Icons.remove_outlined),
                              onPressed: () => setState(() {
                                    _lines[i].qty -= 1;
                                    if (_lines[i].qty <= 0) {
                                      _lines.removeAt(i);
                                    }
                                  })),
                          IconButton(
                              icon: const Icon(
                                  Icons.add_outlined),
                              onPressed: () => setState(
                                  () => _lines[i].qty += 1)),
                          IconButton(
                              icon: const Icon(
                                  Icons.delete_outline),
                              onPressed: () => setState(
                                  () => _lines.removeAt(i))),
                        ],
                      ),
                    ),
                    TextFormField(
                      key: ValueKey('pi-cost-$i'),
                      initialValue:
                          _lines[i].cost.toString(),
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                                  decimal: true),
                      textDirection:
                          TextDirection.ltr,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'سعر الشراء من المورد',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8),
                      ),
                      onChanged: (v) {
                        final d =
                            double.tryParse(v);
                        if (d != null && d >= 0) {
                          // بدون setState عشان الفوكس ميضيعش أثناء الكتابة.
                          _lines[i].cost = d;
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // ---- الضريبة: تشيك بوكس واحد آخر الفاتورة ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('الفاتورة عليها ضريبة؟'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _hasTax,
                    onChanged: (v) =>
                        setState(() => _hasTax = v),
                  ),
                  if (_hasTax)
                    TextField(
                      controller: _invoiceTax,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'قيمة الضريبة %',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---- إجمالي الفاتورة ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(children: [
                    const Expanded(
                        child: Text('إجمالي الأصناف')),
                    Text(_subtotal.toStringAsFixed(2),
                        textDirection: TextDirection.ltr),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Expanded(
                        child: Text('الضريبة')),
                    Text(_taxAmount.toStringAsFixed(2),
                        textDirection: TextDirection.ltr),
                  ]),
                  const Divider(),
                  Row(children: [
                    const Expanded(
                        child: Text('إجمالي الفاتورة',
                            style: TextStyle(
                                fontWeight:
                                    FontWeight.bold))),
                    Text(_grandTotal.toStringAsFixed(2),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (resolveBackendMode() == BackendMode.local) ...[
            FilledButton.icon(
              onPressed: _saving ? null : _saveDirect,
              icon: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline,
                      size: 20),
              label: const Text(
                  'حفظ الفاتورة (اعتماد ونزول المخزون)'),
            ),
            const SizedBox(height: 4),
            const Text(
              'نسخة الجهاز: الحفظ يعتمد الفاتورة وينزل الكمية في المخزن فورا بدون موافقات.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ] else
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
