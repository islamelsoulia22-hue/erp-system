import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/sales_repository.dart';
import '../../domain/sales.dart';

final salesSearchProvider = StateProvider<String>((ref) => '');
final salesStatusFilterProvider = StateProvider<String?>((ref) => null);
final salesFromDateProvider = StateProvider<DateTime?>((ref) => null);
final salesToDateProvider = StateProvider<DateTime?>((ref) => null);

final salesPageProvider = FutureProvider.autoDispose
    .family<PagedData<SalesInvoice>, int>((ref, page) async {
  final repo = ref.watch(salesRepositoryProvider);
  final q = ref.watch(salesSearchProvider);
  final status = ref.watch(salesStatusFilterProvider);
  final from = ref.watch(salesFromDateProvider);
  final to = ref.watch(salesToDateProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(
        query: q,
        status: status,
        from: from,
        to: to,
        page: page,
        pageSize: ps),
    repo.count(query: q, status: status, from: from, to: to),
  ]);
  return PagedData(res[0] as List<SalesInvoice>, res[1] as int);
});

final salesDetailProvider =
    FutureProvider.autoDispose.family<SalesInvoice?, String>((ref, id) {
  return ref.watch(salesRepositoryProvider).getById(id);
});

final salesItemsProvider =
    FutureProvider.autoDispose.family<List<SalesInvoiceItem>, String>(
        (ref, id) {
  return ref.watch(salesRepositoryProvider).itemsOf(id);
});

final paymentMethodsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(salesRepositoryProvider).paymentMethods();
});
