import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/warehouses_repository.dart';
import '../../domain/warehouse.dart';

final warehousesListProvider =
    FutureProvider.autoDispose<List<Warehouse>>((ref) {
  return ref.watch(warehousesRepositoryProvider).list();
});

final warehouseDetailProvider =
    FutureProvider.autoDispose.family<Warehouse?, String>((ref, id) {
  return ref.watch(warehousesRepositoryProvider).getById(id);
});

final warehouseStockProvider =
    FutureProvider.autoDispose.family<List<StockLine>, String>(
        (ref, warehouseId) {
  return ref.watch(warehousesRepositoryProvider).stockOf(warehouseId);
});

final warehouseMovementsProvider =
    FutureProvider.autoDispose.family<List<StockMovement>, String>(
        (ref, warehouseId) {
  return ref.watch(warehousesRepositoryProvider).movementsOf(warehouseId);
});

final inventorySearchProvider = StateProvider<String>((ref) => '');

final inventoryOverviewProvider =
    FutureProvider.autoDispose<List<StockLine>>((ref) {
  return ref
      .watch(warehousesRepositoryProvider)
      .overview(query: ref.watch(inventorySearchProvider));
});
