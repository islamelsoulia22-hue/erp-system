import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/yad_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';
import '../../../sales/presentation/widgets/barcode_scan_sheet.dart';

/// Modern product management: dense toolbar (search + filters +
/// actions), data table on desktop, compact cards on mobile.
/// Numbered pagination (10/page).
class ProductsListScreen extends ConsumerStatefulWidget {
  const ProductsListScreen({super.key});

  @override
  ConsumerState<ProductsListScreen> createState() =>
      _ProductsListScreenState();
}

class _ProductsListScreenState
    extends ConsumerState<ProductsListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int p) {
    setState(() => _page = p);
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    }
  }

  void _resetPage() {
    if (_page != 0) setState(() => _page = 0);
  }

  Future<void> _scan() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BarcodeScanSheet(),
    );
    if (code == null || code.isEmpty || !mounted) return;
    try {
      final product = await ref
          .read(productsRepositoryProvider)
          .findByBarcode(code);
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'لم يتم العثور على صنف بهذا الباركود'),
            action: SnackBarAction(
              label: 'بحث يدوي',
              onPressed: () => _submitSearch(
                  _search.text),
            ),
          ),
        );
        return;
      }
      context.push('/products/${product.id}');
    } catch (e) {
      debugPrint('barcode lookup error: $e (${e.runtimeType})');
      if (!mounted) return;
      final msg = e is AppFailure
          ? e.messageAr
          : 'حدث خطأ أثناء البحث بالباركود.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _submitSearch(String v) {
    ref.read(productSearchQueryProvider.notifier).state = v;
    _resetPage();
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canCreate = perms.can(Permissions.productsCreate);
    final canEdit = perms.can(Permissions.productsEdit);
    final isManager = perms.isCompanyManager;
    final isCatManager =
        isManager || perms.can(Permissions.productsCreate);
    final cats = ref.watch(productCategoriesProvider);
    final categoryId =
        ref.watch(productCategoryFilterProvider);
    final activeOnly =
        ref.watch(productActiveOnlyProvider);
    final page = ref.watch(productsPageProvider(_page));

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(productsPageProvider(_page).future),
        child: ListView(
          controller: _scroll,
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            _Toolbar(
              search: _search,
              onSubmitted: _submitSearch,
              onClear: () => _submitSearch(''),
              categories: cats.maybeWhen(
                  data: (c) => c, orElse: () => []),
              categoryId: categoryId,
              onCategory: (v) {
                ref
                    .read(productCategoryFilterProvider
                        .notifier)
                    .state = v;
                _resetPage();
              },
              activeOnly: activeOnly,
              onActive: (v) {
                ref
                    .read(productActiveOnlyProvider
                        .notifier)
                    .state = v;
                _resetPage();
              },
              canCreate: canCreate,
              onAdd: () =>
                  context.push('/products/new'),
              onScan: _scan,
              showPrices: isManager,
              onPrices: () =>
                  context.push('/products/purchase-prices'),
              showSuppliers: canEdit,
              onSuppliers: () =>
                  context.push('/products/suppliers'),
              showCategories: isCatManager,
              onCategories: () =>
                  context.push('/products/categories'),
              onBarcodes: () =>
                  context.push('/products/barcodes'),
            ),
            const SizedBox(height: AppSpacing.md),
            ...page.when(
              loading: () => [
                const Padding(
                  padding:
                      EdgeInsets.all(AppSpacing.mdx),
                  child: Center(
                      child:
                          CircularProgressIndicator()),
                ),
              ],
              error: (e, _) {
                debugPrint(
                    'products load error: $e (${e.runtimeType})');
                final msg = e is AppFailure
                    ? e.messageAr
                    : 'حدث خطأ أثناء تنفيذ العملية، برجاء المحاولة مرة أخرى.';
                return [
                  Center(child: Text(msg)),
                ];
              },
              data: (paged) => [
                if (paged.items.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'لا توجد أصناف مطابقة',
                    subtitle:
                        'جرب كلمة بحث مختلفة أو أضف صنفا جديدا',
                  )
                else
                  ResponsiveTable<Product>(
                    columns: [
                      TableColumn(
                          label: 'الصنف',
                          value: (p) => p.name),
                      TableColumn(
                          label: 'SKU', value: (p) => p.sku),
                      TableColumn(
                          label: 'الباركود',
                          value: (p) =>
                              p.primaryBarcode ?? '—'),
                      TableColumn(
                          label: 'الفئة',
                          value: (p) =>
                              p.categoryName ?? '—'),
                      TableColumn(
                          label: 'سعر الشراء',
                          numeric: true,
                          value: (p) => AppFormat.money(
                              p.purchasePrice,
                              suffix: '')),
                      TableColumn(
                          label: 'سعر البيع',
                          numeric: true,
                          value: (p) => AppFormat.money(
                              p.salePrice,
                              suffix: '')),
                      TableColumn(
                          label: 'الحالة',
                          value: (p) =>
                              p.isActive ? 'نشط' : 'موقوف'),
                    ],
                    rows: paged.items,
                    onTap: (p) =>
                        context.push('/products/${p.id}'),
                    cardBuilder: (p) => AppCard(
                      onTap: () =>
                          context.push('/products/${p.id}'),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const YadIconTile(
                                  icon: Icons.inventory_2_outlined,
                                  size: 50,
                                  radius: 17),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontSize: 17),
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis),
                                    Text(
                                      '${p.sku} • ${p.categoryName ?? 'بدون فئة'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              AppStatus.badge(
                                  p.isActive ? 'ACTIVE' : 'INACTIVE'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                  child: _PriceTile(
                                      label: 'سعر الشراء',
                                      value: p.purchasePrice)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _PriceTile(
                                      label: 'سعر البيع',
                                      value: p.salePrice)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                AppPagination(
                  page: _page,
                  total: paged.total,
                  onGo: _go,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController search;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final List<ProductCategory> categories;
  final String? categoryId;
  final ValueChanged<String?> onCategory;
  final bool activeOnly;
  final ValueChanged<bool> onActive;
  final bool canCreate;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final bool showPrices;
  final VoidCallback onPrices;
  final bool showSuppliers;
  final VoidCallback onSuppliers;
  final bool showCategories;
  final VoidCallback onCategories;
  final VoidCallback onBarcodes;
  const _Toolbar({
    required this.search,
    required this.onSubmitted,
    required this.onClear,
    required this.categories,
    required this.categoryId,
    required this.onCategory,
    required this.activeOnly,
    required this.onActive,
    required this.canCreate,
    required this.onAdd,
    required this.onScan,
    this.showPrices = false,
    required this.onPrices,
    this.showSuppliers = false,
    required this.onSuppliers,
    this.showCategories = false,
    required this.onCategories,
    required this.onBarcodes,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: search,
                  hint:
                      'ابحث باسم الصنف أو SKU أو Barcode',
                  onSubmitted: onSubmitted,
                  onClear: onClear,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TapScale(
                onTap: onScan,
                semanticLabel: 'مسح Barcode',
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.qr_code_scanner_outlined,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          if (canCreate ||
              showPrices ||
              showSuppliers ||
              showCategories) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (canCreate)
                    _ActionPill(
                        label: '+ إضافة صنف',
                        onTap: onAdd,
                        primary: true),
                  if (showCategories)
                    _ActionPill(label: 'الفئات', onTap: onCategories),
                  if (showSuppliers)
                    _ActionPill(
                        label: 'مورد الأصناف', onTap: onSuppliers),
                  if (showPrices)
                    _ActionPill(label: 'أسعار الشراء', onTap: onPrices),
                  _ActionPill(
                      label: 'باركود الأصناف', onTap: onBarcodes),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<
                    String?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(
                      labelText: 'الفئة',
                      prefixIcon: Icon(
                          Icons.category_outlined,
                          size: 18)),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('كل الفئات')),
                    for (final c in categories)
                      DropdownMenuItem(
                          value: c.id,
                          child: Text(c.display,
                              overflow: TextOverflow
                                  .ellipsis)),
                  ],
                  onChanged: onCategory,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterChip(
                label: const Text('النشط فقط'),
                selected: activeOnly,
                onSelected: onActive,
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _ActionPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _ActionPill(
      {required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: TapScale(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: primary ? AppColors.actionGradient : null,
            color: primary ? null : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: primary
                ? null
                : Border.all(color: AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primary
                      ? Colors.white
                      : theme.colorScheme.onSurface)),
        ),
      ),
    );
  }
}

class _PriceTile extends StatelessWidget {
  final String label;
  final double value;
  const _PriceTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkBackground : AppColors.mist,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(AppFormat.money(value, suffix: ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontSize: 19)),
              ),
              const SizedBox(width: 4),
              Text('ج.م', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
