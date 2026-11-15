import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/expenses_repository.dart';
import '../providers/expenses_providers.dart';

/// إدارة تصنيفات المصروفات — للمدير فقط (users.manage).
class ExpenseCategoriesScreen extends ConsumerStatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  ConsumerState<ExpenseCategoriesScreen> createState() =>
      _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState
    extends ConsumerState<ExpenseCategoriesScreen> {
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    final isManager = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.usersManage),
          orElse: () => false,
        );
    if (!isManager) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'للإدارة فقط',
      );
    }
    final cats = ref.watch(expenseCategoriesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addSheet(context, ref),
        child: const Icon(Icons.add_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(expenseCategoriesProvider),
        child: cats.when(
          loading: () =>
              const LoadingSkeleton(rows: 6),
          error: (_, _) => const ErrorState(),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(
                    child: Text('لا توجد تصنيفات — أضف أول تصنيف'))
              ]);
            }
            final items = paginateLocal(list, _page);
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(
                  height: AppSpacing.sm),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return AppPagination(
                    page: _page,
                    total: list.length,
                    onGo: _go,
                  );
                }
                final c = items[i];
                return AppCard(
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(
                          Icons.category_outlined,
                          size: 20),
                      const SizedBox(
                          width: AppSpacing.sm),
                      Expanded(
                        child: Text(c.display,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _addSheet(BuildContext context, WidgetRef ref) {
    final name = TextEditingController();
    final nameAr = TextEditingController();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('+ إضافة تصنيف مصروف',
                style: TextStyle(
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'الاسم *')),
            const SizedBox(height: 8),
            TextField(
                controller: nameAr,
                decoration: const InputDecoration(
                    labelText: 'الاسم بالعربي')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                try {
                  await ref
                      .read(expensesRepositoryProvider)
                      .createCategory(
                        name: name.text,
                        nameAr: nameAr.text,
                      );
                  ref.invalidate(
                      expenseCategoriesProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                            content: Text(e is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء التصنيف.')));
                  }
                }
              },
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }
}
