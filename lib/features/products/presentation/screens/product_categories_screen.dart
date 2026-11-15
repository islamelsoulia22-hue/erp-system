import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';
import '../providers/products_providers.dart';

/// إدارة فئات الأصناف — للمدير فقط.
/// مسح = إيقاف (إخفاء) مع إمكانية الاسترجاع (إضافتها تاني)،
/// + حذف نهائي لو مفيش أصناف مرتبطة.
/// فئة بكر الباركود محمية: قفل ولا يمكن مسحها أو إيقافها.
class ProductCategoriesScreen extends ConsumerStatefulWidget {
  const ProductCategoriesScreen({super.key});

  @override
  ConsumerState<ProductCategoriesScreen> createState() =>
      _ProductCategoriesScreenState();
}

class _ProductCategoriesScreenState
    extends ConsumerState<ProductCategoriesScreen> {
  bool _ensured = false;

  bool _isManager(PermissionSet p) =>
      p.isCompanyManager || p.can(Permissions.productsCreate);

  /// أول فتح للمدير: يتأكد إن فئة بكر الباركود موجودة (يعملها لو ناقصة).
  Future<void> _ensureRoll() async {
    if (_ensured) return;
    _ensured = true;
    try {
      final created = await ref
          .read(productsRepositoryProvider)
          .ensureBarcodeRollCategory();
      if (created != null && mounted) {
        ref
          ..invalidate(productCategoriesAllProvider)
          ..invalidate(productCategoriesProvider);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    if (!_isManager(perms)) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'للإدارة فقط',
        subtitle: 'إدارة الفئات متاحة لمدير الشركة فقط.',
      );
    }
    // تأكد من وجود فئة البكر (تتعمل تلقائيا أول مرة).
    Future.microtask(_ensureRoll);
    final cats = ref.watch(productCategoriesAllProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'فئة جديدة',
        onPressed: () => _addSheet(context, ref),
        child: const Icon(Icons.add_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(productCategoriesAllProvider),
        child: cats.when(
          loading: () => const LoadingSkeleton(rows: 6),
          error: (e, _) => ErrorState(
            message: e is AppFailure
                ? e.messageAr
                : 'تعذر تحميل الفئات.',
            onRetry: () =>
                ref.invalidate(productCategoriesAllProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                Center(
                    child:
                        Text('لا توجد فئات — أضف أول فئة'))
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(
                  height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final c = list[i];
                final protected =
                    isBarcodeRollCategory(c);
                return AppCard(
                  padding: const EdgeInsets.all(
                      AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        protected
                            ? Icons.lock_outline
                            : Icons.category_outlined,
                        size: 20,
                        color: protected
                            ? Colors.amber.shade800
                            : null,
                      ),
                      const SizedBox(
                          width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(c.display,
                                      style:
                                          Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                ),
                                if (protected)
                                  Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 8,
                                        vertical: 2),
                                    decoration:
                                        BoxDecoration(
                                      color: Colors
                                          .amber.shade100,
                                      borderRadius:
                                          BorderRadius.circular(
                                              12),
                                    ),
                                    child: const Text(
                                      'محمية',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight:
                                              FontWeight.bold),
                                    ),
                                  ),
                                if (!c.isActive &&
                                    !protected)
                                  Container(
                                    margin:
                                        const EdgeInsets
                                            .symmetric(
                                                horizontal:
                                                    4),
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 8,
                                        vertical: 2),
                                    decoration:
                                        BoxDecoration(
                                      color: Colors
                                          .grey.shade300,
                                      borderRadius:
                                          BorderRadius.circular(
                                              12),
                                    ),
                                    child: const Text(
                                      'موقوفة',
                                      style: TextStyle(
                                          fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                            if (c.code != null)
                              Text(
                                c.code!,
                                textDirection:
                                    TextDirection.ltr,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color:
                                            Colors.grey),
                              ),
                            if (protected)
                              Text(
                                'فئة بكر الباركود — لا يمكن مسحها أو إيقافها.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors
                                            .amber
                                            .shade800),
                              ),
                          ],
                        ),
                      ),
                      if (!protected && c.isActive)
                        IconButton(
                          tooltip: 'مسح (إيقاف)',
                          icon: const Icon(
                              Icons
                                  .delete_outline,
                              color: Colors.red),
                          onPressed: () =>
                              _deactivate(
                                  context, ref, c),
                        ),
                      if (!protected && !c.isActive) ...[
                        IconButton(
                          tooltip:
                              'استرجاع (إضافتها تاني)',
                          icon: const Icon(
                              Icons
                                  .restore_outlined,
                              color: Colors.green),
                          onPressed: () =>
                              _restore(
                                  context, ref, c),
                        ),
                        IconButton(
                          tooltip: 'حذف نهائي',
                          icon: const Icon(
                              Icons
                                  .delete_forever_outlined,
                              color: Colors.red),
                          onPressed: () =>
                              _hardDelete(
                                  context, ref, c),
                        ),
                      ],
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

  Future<void> _deactivate(BuildContext context,
      WidgetRef ref, ProductCategory c) async {
    if (!await confirmDelete(
        context, 'الفئة "${c.display}" (سيتم إخفاؤها ويمكن استرجاعها)')) {
      return;
    }
    try {
      await ref
          .read(productsRepositoryProvider)
          .deactivateCategory(c);
      ref
        ..invalidate(productCategoriesAllProvider)
        ..invalidate(productCategoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'تم مسح الفئة (إيقاف) — تقدر تسترجعها تاني.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e is AppFailure
                    ? e.messageAr
                    : deleteErrorMessage(e))));
      }
    }
  }

  Future<void> _restore(BuildContext context,
      WidgetRef ref, ProductCategory c) async {
    try {
      await ref
          .read(productsRepositoryProvider)
          .restoreCategory(c.id);
      ref
        ..invalidate(productCategoriesAllProvider)
        ..invalidate(productCategoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'تمت إضافة الفئة "${c.display}" تاني.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e is AppFailure
                    ? e.messageAr
                    : 'تعذر استرجاع الفئة.')));
      }
    }
  }

  Future<void> _hardDelete(BuildContext context,
      WidgetRef ref, ProductCategory c) async {
    if (!await confirmDelete(
        context, 'الحذف النهائي للفئة "${c.display}"')) {
      return;
    }
    try {
      await ref
          .read(productsRepositoryProvider)
          .deleteCategoryHard(c);
      ref
        ..invalidate(productCategoriesAllProvider)
        ..invalidate(productCategoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('تم حذف الفئة نهائيا.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e is AppFailure
                    ? e.messageAr
                    : deleteErrorMessage(e))));
      }
    }
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
            bottom:
                MediaQuery.of(ctx).viewInsets.bottom +
                    16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text('+ إضافة فئة',
                style: TextStyle(
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'اسم الفئة *')),
            const SizedBox(height: 8),
            TextField(
                controller: nameAr,
                decoration: const InputDecoration(
                    labelText:
                        'الاسم بالعربي (اختياري)')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty &&
                    nameAr.text.trim().isEmpty) {
                  return;
                }
                try {
                  await ref
                      .read(productsRepositoryProvider)
                      .createCategory(
                        name: name.text.trim().isEmpty
                            ? nameAr.text
                            : name.text,
                        nameAr: nameAr.text,
                      );
                  ref
                    ..invalidate(
                        productCategoriesAllProvider)
                    ..invalidate(
                        productCategoriesProvider);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(
                            content: Text(e
                                    is AppFailure
                                ? e.messageAr
                                : 'تعذر إنشاء الفئة.')));
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
