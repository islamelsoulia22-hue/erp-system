import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/manufacturing_repository.dart';
import '../../domain/manufacturing.dart';

final czSearchProvider = StateProvider<String>((ref) => '');

final czPageProvider = FutureProvider.autoDispose
    .family<PagedData<CustomizedItem>, int>((ref, page) async {
  final repo = ref.watch(manufacturingRepositoryProvider);
  final q = ref.watch(czSearchProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.listCustomized(query: q, page: page, pageSize: ps),
    repo.countCustomized(query: q),
  ]);
  return PagedData(res[0] as List<CustomizedItem>, res[1] as int);
});

final czDetailProvider =
    FutureProvider.autoDispose.family<CustomizedItem?, String>(
        (ref, id) {
  return ref.watch(manufacturingRepositoryProvider).getCustomized(id);
});

final moPageProvider = FutureProvider.autoDispose
    .family<PagedData<ManufacturingOrder>, int>((ref, page) async {
  final repo = ref.watch(manufacturingRepositoryProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.listOrders(page: page, pageSize: ps),
    repo.countOrders(),
  ]);
  return PagedData(
      res[0] as List<ManufacturingOrder>, res[1] as int);
});

final moDetailProvider =
    FutureProvider.autoDispose.family<ManufacturingOrder?, String>(
        (ref, id) {
  return ref.watch(manufacturingRepositoryProvider).getOrder(id);
});

final moMaterialsProvider =
    FutureProvider.autoDispose.family<List<ManufacturingMaterial>, String>(
        (ref, id) {
  return ref.watch(manufacturingRepositoryProvider).materialsOf(id);
});
