import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';

/// قسم تعديل أسعار الشراء — للمدير فقط.
/// جدول سريع: كل صنف في سطر مع خانة سعر الشراء + حفظ فوري،
/// مع بحث وزرار "حفظ الكل" للصفوف المتعدلة.
class PurchasePricesScreen extends ConsumerStatefulWidget {
  const PurchasePricesScreen({super.key});

  @override
  ConsumerState<PurchasePricesScreen> createState() =>
      _PurchasePricesScreenState();
}

class _PurchasePricesScreenState
    extends ConsumerState<PurchasePricesScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  final _items = <Product>[];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  // القيم المتعدلة محليا: productId -> السعر الجديد.
  final _edits = <String, double>{};
  final _savingIds = <String>{};
  bool _savingAll = false;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPage);
  }

  /// تحميل صفحة واحدة مرقمة (10 عناصر) + إجمالي العدد.
  Future<void> _loadPage() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await ref
          .read(productsRepositoryProvider)
          .searchPaged(query: _query, page: _page);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(res.items);
        _total = res.total;
        // شيل التعديلات اللي بقت مطابقة للسعر المحفوظ.
        for (final p in res.items) {
          _edits.removeWhere((id, v) =>
              id == p.id && (v - p.purchasePrice).abs() < 1e-9);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر تحميل الأصناف.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
    _loadPage();
  }

  void _onSearch(String v) {
    _query = v.trim();
    _edits.clear();
    setState(() => _page = 0);
    _loadPage();
  }

  void _onRowChanged(String id, double? newPrice) {
    final matches = _items.where((e) => e.id == id).toList();
    if (matches.isEmpty) return;
    final p = matches.first;
    setState(() {
      if (newPrice == null ||
          (newPrice - p.purchasePrice).abs() < 1e-9) {
        _edits.remove(id);
      } else {
        _edits[id] = newPrice;
      }
    });
  }

  Future<void> _saveOne(String id) async {
    final price = _edits[id];
    if (price == null || _savingIds.contains(id)) return;
    setState(() => _savingIds.add(id));
    try {
      await ref
          .read(productsRepositoryProvider)
          .update(id, {'purchase_price': price});
      ref
        ..invalidate(productsPageProvider)
        ..invalidate(productDetailProvider(id));
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((e) => e.id == id);
        if (i >= 0) {
          final old = _items[i];
          _items[i] = Product(
            id: old.id,
            sku: old.sku,
            name: old.name,
            description: old.description,
            categoryId: old.categoryId,
            categoryName: old.categoryName,
            unitId: old.unitId,
            unitName: old.unitName,
            purchasePrice: price,
            salePrice: old.salePrice,
            supplierId: old.supplierId,
            supplierName: old.supplierName,
            deviceType: old.deviceType,
            brand: old.brand,
            model: old.model,
            taxable: old.taxable,
            taxRate: old.taxRate,
            minimumStock: old.minimumStock,
            trackInventory: old.trackInventory,
            isCustomizable: old.isCustomizable,
            isActive: old.isActive,
            primaryBarcode: old.primaryBarcode,
          );
        }
        _edits.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سعر الشراء.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حفظ السعر.')));
    } finally {
      if (mounted) setState(() => _savingIds.remove(id));
    }
  }

  Future<void> _saveAll() async {
    if (_edits.isEmpty || _savingAll) return;
    setState(() => _savingAll = true);
    final ids = _edits.keys.toList();
    var ok = 0;
    try {
      final repo = ref.read(productsRepositoryProvider);
      for (final id in ids) {
        final price = _edits[id];
        if (price == null) continue;
        try {
          await repo.update(id, {'purchase_price': price});
          ok++;
          if (mounted) {
            setState(() {
              final i = _items.indexWhere((e) => e.id == id);
              if (i >= 0) {
                final old = _items[i];
                _items[i] = Product(
                  id: old.id,
                  sku: old.sku,
                  name: old.name,
                  description: old.description,
                  categoryId: old.categoryId,
                  categoryName: old.categoryName,
                  unitId: old.unitId,
                  unitName: old.unitName,
                  purchasePrice: price,
                  salePrice: old.salePrice,
                  supplierId: old.supplierId,
                  supplierName: old.supplierName,
                  deviceType: old.deviceType,
                  brand: old.brand,
                  model: old.model,
                  taxable: old.taxable,
                  taxRate: old.taxRate,
                  minimumStock: old.minimumStock,
                  trackInventory: old.trackInventory,
                  isCustomizable: old.isCustomizable,
                  isActive: old.isActive,
                  primaryBarcode: old.primaryBarcode,
                );
              }
              _edits.remove(id);
            });
          }
        } catch (_) {
          // كمّل الباقي واعرض الملخص في الآخر.
        }
      }
      ref.invalidate(productsPageProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'تم حفظ $ok من ${ids.length} صنف.')));
      }
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isManager = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.isCompanyManager,
          orElse: () => false,
        );
    if (!isManager) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'للإدارة فقط',
        subtitle: 'تعديل أسعار الشراء متاح لمدير الشركة فقط.',
      );
    }

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () async {
          setState(() => _page = 0);
          await _loadPage();
        },
        child: ListView(
          controller: _scroll,
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SearchField(
                          controller: _search,
                          hint: 'ابحث باسم الصنف أو SKU',
                          onSubmitted: _onSearch,
                          onClear: () {
                            _search.clear();
                            _onSearch('');
                          },
                        ),
                      ),
                      const SizedBox(
                          width: AppSpacing.sm),
                      FilledButton(
                        onPressed: (_edits.isEmpty ||
                                _savingAll)
                            ? null
                            : _saveAll,
                        child: _savingAll
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                            : Text(
                                'حفظ الكل (${_edits.length})'),
                      ),
                    ],
                  ),
                  if (_edits.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'عدّلت أسعار — دوس حفظ الكل أو احفظ كل سطر لوحده.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_items.isEmpty && !_loading)
              const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'لا توجد أصناف مطابقة',
              )
            else
              for (final p in _items)
                _PurchasePriceRow(
                  key: ValueKey('pp-${p.id}'),
                  product: p,
                  saving:
                      _savingIds.contains(p.id) ||
                          _savingAll,
                  onChanged: (v) =>
                      _onRowChanged(p.id, v),
                  onSave: () => _saveOne(p.id),
                ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.mdx),
                child: Center(
                    child:
                        CircularProgressIndicator()),
              )
            else
              AppPagination(
                page: _page,
                total: _total,
                onGo: _go,
              ),
          ],
        ),
      ),
    );
  }
}

/// سطر واحد: الاسم + سعر البيع كمرجع + خانة سعر الشراء + حفظ.
class _PurchasePriceRow extends StatefulWidget {
  final Product product;
  final bool saving;
  final ValueChanged<double?> onChanged;
  final VoidCallback onSave;
  const _PurchasePriceRow({
    super.key,
    required this.product,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<_PurchasePriceRow> createState() =>
      _PurchasePriceRowState();
}

class _PurchasePriceRowState
    extends State<_PurchasePriceRow> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.product.purchasePrice.toString());
  }

  @override
  void didUpdateWidget(
      covariant _PurchasePriceRow old) {
    super.didUpdateWidget(old);
    if (old.product.id != widget.product.id) {
      _ctrl.text =
          widget.product.purchasePrice.toString();
    } else if (!_focus.hasFocus &&
        _ctrl.text !=
            widget.product.purchasePrice.toString()) {
      _ctrl.text =
          widget.product.purchasePrice.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_ctrl.text.trim());
  bool get _valid => _parsed != null && _parsed! >= 0;
  bool get _dirty =>
      _valid &&
      (_parsed! - widget.product.purchasePrice).abs() >
          1e-9;

  String _margin() {
    final buy = widget.product.purchasePrice;
    final sell = widget.product.salePrice;
    if (buy <= 0) return 'هامش —';
    final m = (sell - buy) / buy * 100;
    return 'هامش ${m.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis),
              ),
              if (_dirty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                  child: const Text('متعدل',
                      style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          Text(
            '${p.sku} • بيع ${AppFormat.money(p.salePrice)} • ${_margin()}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  enabled: !widget.saving,
                  keyboardType: const TextInputType
                      .numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'سعر الشراء',
                    isDense: true,
                    errorText: _ctrl.text.isEmpty ||
                            _valid
                        ? null
                        : 'رقم غير صالح',
                  ),
                  onChanged: (_) {
                    widget.onChanged(
                        _valid ? _parsed : null);
                    setState(() {});
                  },
                  onSubmitted: (_) {
                    if (_dirty) widget.onSave();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_dirty && !widget.saving)
                    ? widget.onSave
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12),
                ),
                child: widget.saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white))
                    : const Text('حفظ'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
