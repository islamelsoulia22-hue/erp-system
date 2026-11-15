import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../data/expenses_repository.dart';
import '../../domain/expense.dart';

final expenseSearchProvider = StateProvider<String>((ref) => '');
final expenseStatusProvider = StateProvider<String?>((ref) => null);
final expenseCategoryProvider =
    StateProvider<String?>((ref) => null);
final expenseFromDateProvider =
    StateProvider<DateTime?>((ref) => null);
final expenseToDateProvider =
    StateProvider<DateTime?>((ref) => null);

final expensesPageProvider = FutureProvider.autoDispose
    .family<PagedData<Expense>, int>((ref, page) async {
  final repo = ref.watch(expensesRepositoryProvider);
  final q = ref.watch(expenseSearchProvider);
  final status = ref.watch(expenseStatusProvider);
  final cat = ref.watch(expenseCategoryProvider);
  final from = ref.watch(expenseFromDateProvider);
  final to = ref.watch(expenseToDateProvider);
  const ps = AppConstants.listPageSize;
  final res = await Future.wait([
    repo.list(
        query: q,
        status: status,
        categoryId: cat,
        from: from,
        to: to,
        page: page,
        pageSize: ps),
    repo.count(
        query: q,
        status: status,
        categoryId: cat,
        from: from,
        to: to),
  ]);
  return PagedData(res[0] as List<Expense>, res[1] as int);
});

final expenseDetailProvider = FutureProvider.autoDispose
    .family<Expense?, String>((ref, id) {
  return ref.watch(expensesRepositoryProvider).getById(id);
});

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) {
  return ref.watch(expensesRepositoryProvider).categories();
});
