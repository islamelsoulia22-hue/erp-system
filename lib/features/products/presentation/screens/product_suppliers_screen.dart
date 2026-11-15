import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../suppliers/data/suppliers_repository.dart';
import '../../../suppliers/presentation/providers/suppliers_providers.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';

/// قسم تعديل أسماء موردي الأصناف — لمن لديه صلاحية تعديل الموردين.
/// جدول سريع: كل صنف في سطر مع خانة اسم مورده + حفظ فوري،
/// مع بحث وزرار "حفظ الكل" للصفوف المتعدلة.
/// الاسم يتعدل على سجل المورد نفسه، فيسمع في الموردين وفي كل
/// أصناف نفس المورد. الأصناف بدون مورد تُعيَّن من فورم الصنف.
class ProductSuppliersScreen extends ConsumerStatefulWidget {
  const ProductSuppliersScreen({super.key});

  @override
  ConsumerState<ProductSuppliersScreen> createState() =>
      _ProductSuppliersScreenState();
}

class _ProductSuppliersScreenState
    extends ConsumerState<ProductSuppliersScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  final _items = <Product>[];
  int _total = 0;
  int _page = 0;
  bool _loading = false;
  // القيم المتعدلة محليا: productId -> اسم المورد الجديد.
  final _edits = <String, String>{};
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
        // شيل التعديلات اللي بقت مطابقة للمحفوظ.
        for (final p in res.items) {
          _edits.removeWhere((id, v) =>
              id == p.id &&
              v.trim() == (p.supplierName ?? '').trim());
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

  void _onRowChanged(String id, String? newName) {
    final matches = _items.where((e) => e.id == id).toList();
    if (matches.isEmpty) return;
    final p = matches.first;
    final saved = (p.supplierName ?? '').trim();
    setState(() {
      if (newName == null || newName.trim().isEmpty || newName.trim() == saved) {
        _edits.remove(id);
      } else {
        _edits[id] = newName.trim();
      }
    });
  }

  /// حدّث الاسم محليا لكل الصفوف اللي شايرة نفس المورد.
  void _applyLocal(String supplierId, String newName) {
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        final old = _items[i];
        if (old.supplierId == supplierId) {
          _items[i] = Product(
            id: old.id,
            sku: old.sku,
            name: old.name,
            description: old.description,
            categoryId: old.categoryId,
            categoryName: old.categoryName,
            unitId: old.unitId,
            unitName: old.unitName,
            purchasePrice: old.purchasePrice,
            salePrice: old.salePrice,
            supplierId: old.supplierId,
            supplierName: newName,
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
          _edits.remove(old.id);
        }
      }
    });
  }

  void _invalidateAfter(String supplierId, String productId) {
    ref
      ..invalidate(productsPageProvider)
      ..invalidate(productDetailProvider(productId))
      ..invalidate(suppliersPageProvider)
      ..invalidate(supplierDetailProvider(supplierId));
  }

  Future<void> _saveOne(String id) async {
    final newName = _edits[id];
    if (newName == null || _savingIds.contains(id)) return;
    final matches = _items.where((e) => e.id == id).toList();
    if (matches.isEmpty) return;
    final supplierId = matches.first.supplierId;
    if (supplierId == null) return;
    setState(() => _savingIds.add(id));
    try {
      await ref
          .read(suppliersRepositoryProvider)
          .update(supplierId, {'name': newName});
      _invalidateAfter(supplierId, id);
      if (!mounted) return;
      _applyLocal(supplierId, newName);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ اسم المورد.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AppFailure
              ? e.messageAr
              : 'تعذر حفظ الاسم.')));
    } finally {
      if (mounted) setState(() => _savingIds.remove(id));
    }
  }

  Future<void> _saveAll() async {
    if (_edits.isEmpty || _savingAll) return;
    setState(() => _savingAll = true);
    final ids = _edits.keys.toList();
    var ok = 0;
    // مورد واحد ممكن يتكرر في كذا سطر — آخر اسم مكتوب هو اللي يتحفظ.
    final done = <String, String>{};
    try {
      final repo = ref.read(suppliersRepositoryProvider);
      for (final id in ids) {
        final newName = _edits[id];
        if (newName == null) continue;
        final matches = _items.where((e) => e.id == id).toList();
        if (matches.isEmpty) {
          if (mounted) setState(() => _edits.remove(id));
          continue;
        }
        final supplierId = matches.first.supplierId;
        if (supplierId == null) {
          if (mounted) setState(() => _edits.remove(id));
          continue;
        }
        if (done[supplierId] == newName) {
          if (mounted) {
            _applyLocal(supplierId, newName);
          }
          ok++;
          continue;
        }
        try {
          await repo.update(supplierId, {'name': newName});
          done[supplierId] = newName;
          _invalidateAfter(supplierId, id);
          ok++;
          if (mounted) {
            _applyLocal(supplierId, newName);
          }
        } catch (_) {
          // كمّل الباقي واعرض الملخص في الآخر.
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'تم حفظ $ok من ${ids.length} تعديل.')));
      }
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.suppliersEdit),
          orElse: () => false,
        );
    if (!canEdit) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'بدون صلاحية',
        subtitle: 'تعديل أسماء الموردين متاح لمن لديه صلاحية تعديل الموردين.',
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
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'الاسم بيتعدل على سجل المورد نفسه، فيسمع في الموردين وفي كل أصنافه. الأصناف بدون مورد عيّنها من فورم الصنف.',
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
                if (p.supplierId == null)
                  AppCard(
                    key: ValueKey('ps-none-${p.id}'),
                    padding:
                        const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow
                                      .ellipsis),
                              Text(
                                '${p.sku} • بدون مورد',
                                textDirection:
                                    TextDirection.rtl,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => context
                              .push('/products/${p.id}/edit'),
                          child: const Text('تعيين مورد'),
                        ),
                      ],
                    ),
                  )
                else
                  _SupplierNameRow(
                    key: ValueKey('ps-${p.id}'),
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

/// سطر واحد: اسم الصنف + خانة اسم المورد + حفظ.
class _SupplierNameRow extends StatefulWidget {
  final Product product;
  final bool saving;
  final ValueChanged<String?> onChanged;
  final VoidCallback onSave;
  const _SupplierNameRow({
    super.key,
    required this.product,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<_SupplierNameRow> createState() =>
      _SupplierNameRowState();
}

class _SupplierNameRowState
    extends State<_SupplierNameRow> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.product.supplierName ?? '');
  }

  @override
  void didUpdateWidget(
      covariant _SupplierNameRow old) {
    super.didUpdateWidget(old);
    if (old.product.id != widget.product.id) {
      _ctrl.text = widget.product.supplierName ?? '';
    } else if (!_focus.hasFocus &&
        _ctrl.text != (widget.product.supplierName ?? '')) {
      _ctrl.text = widget.product.supplierName ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _dirty {
    final saved = (widget.product.supplierName ?? '').trim();
    final cur = _ctrl.text.trim();
    return cur.isNotEmpty && cur != saved;
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
            p.sku,
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
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد',
                    isDense: true,
                  ),
                  onChanged: (_) {
                    widget.onChanged(
                        _dirty ? _ctrl.text : null);
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
