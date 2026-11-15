import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/customers_repository.dart';
import '../../domain/customer.dart';

final customerSearchProvider = StateProvider<String>((ref) => '');

final customersPageProvider = FutureProvider.autoDispose
    .family<PagedData<Customer>, int>((ref, page) async {
  final repo = ref.watch(customersRepositoryProvider);
  final q = ref.watch(customerSearchProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.search(query: q, page: page, pageSize: ps),
    repo.count(query: q),
  ]);
  return PagedData(res[0] as List<Customer>, res[1] as int);
});

final customerDetailProvider =
    FutureProvider.autoDispose.family<Customer?, String>((ref, id) {
  return ref.watch(customersRepositoryProvider).getById(id);
});

final customerAddressesProvider =
    FutureProvider.autoDispose.family<List<CustomerAddress>, String>(
        (ref, customerId) {
  return ref.watch(customersRepositoryProvider).addressesOf(customerId);
});
