import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_pagination.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';

final productSearchQueryProvider = StateProvider<String>((ref) => '');

/// فلاتر قائمة الأصناف (خادمية — تُصفّر الصفحة عند تغييرها).
final productCategoryFilterProvider =
    StateProvider<String?>((ref) => null);
final productActiveOnlyProvider = StateProvider<bool>((ref) => true);

/// بحث مرقّم الصفحات (10 عناصر/صفحة + إجمالي العدد).
final productsPageProvider = FutureProvider.autoDispose
    .family<PagedData<Product>, int>((ref, page) async {
  final res = await ref
      .watch(productsRepositoryProvider)
      .searchPaged(
        query: ref.watch(productSearchQueryProvider),
        categoryId: ref.watch(productCategoryFilterProvider),
        onlyActive: ref.watch(productActiveOnlyProvider),
        page: page,
      );
  return PagedData(res.items, res.total);
});

final productCategoriesProvider =
    FutureProvider.autoDispose<List<ProductCategory>>((ref) {
  return ref.watch(productsRepositoryProvider).categories();
});

/// كل الفئات للمدير (نشطة + موقوفة) — إدارة المسح والاسترجاع.
final productCategoriesAllProvider =
    FutureProvider.autoDispose<List<ProductCategory>>((ref) {
  return ref.watch(productsRepositoryProvider).categoriesAll();
});

final barcodeMaterialsProvider =
    FutureProvider.autoDispose<List<BarcodeMaterial>>((ref) {
  return ref.watch(productsRepositoryProvider).barcodeMaterials();
});

final productUnitsProvider =
    FutureProvider.autoDispose<List<ProductUnit>>((ref) {
  return ref.watch(productsRepositoryProvider).units();
});

final productDetailProvider =
    FutureProvider.autoDispose.family<Product?, String>((ref, id) {
  return ref.watch(productsRepositoryProvider).getById(id);
});

final productBarcodesProvider =
    FutureProvider.autoDispose.family<List<ProductBarcode>, String>(
        (ref, productId) {
  return ref.watch(productsRepositoryProvider).barcodesOf(productId);
});
