import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/suppliers_repository.dart';
import '../../domain/supplier.dart';

final supplierSearchProvider = StateProvider<String>((ref) => '');

final suppliersPageProvider = FutureProvider.autoDispose
    .family<PagedData<Supplier>, int>((ref, page) async {
  final repo = ref.watch(suppliersRepositoryProvider);
  final q = ref.watch(supplierSearchProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.search(query: q, page: page, pageSize: ps),
    repo.count(query: q),
  ]);
  return PagedData(res[0] as List<Supplier>, res[1] as int);
});

final supplierDetailProvider =
    FutureProvider.autoDispose.family<Supplier?, String>((ref, id) {
  return ref.watch(suppliersRepositoryProvider).getById(id);
});
