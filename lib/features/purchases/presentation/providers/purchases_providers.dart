import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/purchases_repository.dart';
import '../../domain/purchases.dart';

final poSearchProvider = StateProvider<String>((ref) => '');
final poStatusProvider = StateProvider<String?>((ref) => null);
final piSearchProvider = StateProvider<String>((ref) => '');
final piStatusProvider = StateProvider<String?>((ref) => null);
final piFromDateProvider = StateProvider<DateTime?>((ref) => null);
final piToDateProvider = StateProvider<DateTime?>((ref) => null);

final poPageProvider = FutureProvider.autoDispose
    .family<PagedData<PurchaseOrder>, int>((ref, page) async {
  final repo = ref.watch(purchasesRepositoryProvider);
  final q = ref.watch(poSearchProvider);
  final status = ref.watch(poStatusProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.listOrders(
        query: q, status: status, page: page, pageSize: ps),
    repo.countOrders(query: q, status: status),
  ]);
  return PagedData(res[0] as List<PurchaseOrder>, res[1] as int);
});

final poDetailProvider =
    FutureProvider.autoDispose.family<PurchaseOrder?, String>((ref, id) {
  return ref.watch(purchasesRepositoryProvider).getOrder(id);
});

final poItemsProvider =
    FutureProvider.autoDispose.family<List<PurchaseOrderItem>, String>(
        (ref, id) {
  return ref.watch(purchasesRepositoryProvider).orderItems(id);
});

final piPageProvider = FutureProvider.autoDispose
    .family<PagedData<PurchaseInvoice>, int>((ref, page) async {
  final repo = ref.watch(purchasesRepositoryProvider);
  final q = ref.watch(piSearchProvider);
  final status = ref.watch(piStatusProvider);
  final from = ref.watch(piFromDateProvider);
  final to = ref.watch(piToDateProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.listInvoices(
        query: q,
        status: status,
        from: from,
        to: to,
        page: page,
        pageSize: ps),
    repo.countInvoices(
        query: q, status: status, from: from, to: to),
  ]);
  return PagedData(res[0] as List<PurchaseInvoice>, res[1] as int);
});

final piDetailProvider =
    FutureProvider.autoDispose.family<PurchaseInvoice?, String>(
        (ref, id) {
  return ref.watch(purchasesRepositoryProvider).getInvoice(id);
});

final piItemsProvider =
    FutureProvider.autoDispose.family<List<PurchaseInvoiceItem>, String>(
        (ref, id) {
  return ref.watch(purchasesRepositoryProvider).invoiceItems(id);
});
