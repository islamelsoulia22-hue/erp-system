import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../products/data/products_repository.dart';
import '../../../products/domain/product.dart';
import '../../data/warehouses_repository.dart';
import '../../domain/warehouse.dart';
import '../providers/warehouses_providers.dart';

class WarehouseDetailScreen extends ConsumerWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(warehouseDetailProvider(warehouseId));
    final stock = ref.watch(warehouseStockProvider(warehouseId));
    final moves = ref.watch(warehouseMovementsProvider(warehouseId));
    final perms = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const PermissionSet({}),
        );
    final canAdjust = perms.can(Permissions.inventoryAdjust);
    final canTransfer = perms.can(Permissions.inventoryTransfer);
    final canManage = perms.can(Permissions.warehousesManage);
    final isManager = perms.isCompanyManager;

    return detail.when(
      loading: () => const LoadingSkeleton(rows: 6),
      error: (_, _) => const ErrorState(),
        data: (w) {
          if (w == null) {
            return const EmptyState(
              icon: Icons.warehouse_outlined,
              title: 'المخزن غير موجود.',
            );
          }
          return DefaultTabController(
            length: 2,
            child: ResponsiveLayout(
              mobile: ListView(
                padding: EdgeInsets.all(
                    context.contentPadding),
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(w.name,
                                      style: Theme.of(
                                              context)
                                          .textTheme
                                          .headlineSmall),
                                  Text(
                                      '${w.code}${w.location != null ? ' • ${w.location}' : ''}',
                                      textDirection:
                                          TextDirection
                                              .ltr,
                                      style: Theme.of(
                                              context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ),
                            ),
                            if (canManage)
                              IconButton.filledTonal(
                                tooltip: 'تعديل',
                                icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20),
                                onPressed: () =>
                                    context.push(
                                        '/warehouses/$warehouseId/edit'),
                              ),
                            if (isManager)
                              IconButton.filledTonal(
                                tooltip: 'حذف المخزن',
                                icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: AppColors.danger),
                                onPressed: () =>
                                    _deleteWarehouse(
                                        context,
                                        ref,
                                        warehouseId,
                                        w.name),
                              ),
                          ],
                        ),
                        if (canAdjust ||
                            canTransfer) ...[
                          const SizedBox(
                              height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              if (canAdjust)
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _adjustSheet(
                                          context,
                                          ref,
                                          warehouseId),
                                  icon: const Icon(
                                      Icons.tune_outlined,
                                      size: 18),
                                  label: const Text(
                                      'تسوية'),
                                ),
                              if (canTransfer)
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _transferSheet(
                                          context,
                                          ref,
                                          warehouseId),
                                  icon: const Icon(
                                      Icons
                                          .swap_horiz_outlined,
                                      size: 18),
                                  label: const Text(
                                      'تحويل'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(
                      height: AppSpacing.md),
                  Material(
                    color: Theme.of(context)
                        .colorScheme
                        .surface,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                                12)),
                    child: const TabBar(tabs: [
                      Tab(text: 'الرصيد'),
                      Tab(text: 'الحركات'),
                    ]),
                  ),
                  const SizedBox(
                      height: AppSpacing.md),
                  SizedBox(
                    height:
                        MediaQuery.sizeOf(context)
                                .height *
                            0.55,
                    child: TabBarView(children: [
                      stock.when(
                        loading: () =>
                            const LoadingSkeleton(
                                rows: 5),
                        error: (_, _) =>
                            const ErrorState(
                                message:
                                    'تعذر تحميل الرصيد.'),
                        data: (lines) {
                          if (lines.isEmpty) {
                            return const EmptyState(
                              icon: Icons
                                  .inventory_outlined,
                              title: 'لا يوجد رصيد',
                              subtitle:
                                  'استخدم تسوية إدخال لفتح رصيد',
                            );
                          }
                          return RefreshIndicator(
                            onRefresh: () async =>
                                ref.invalidate(
                                    warehouseStockProvider(
                                        warehouseId)),
                            child: ListView(
                              children: [
                                ResponsiveTable<StockLine?>(
                                  columns: [
                                    TableColumn<StockLine?>(
                                        label: 'المنتج',
                                        value: (s) =>
                                            s?.productName ?? ''),
                                    TableColumn<StockLine?>(
                                        label: 'SKU',
                                        value: (s) =>
                                            s?.productSku ?? ''),
                                    TableColumn<StockLine?>(
                                        label: 'المتاح',
                                        numeric: true,
                                        value: (s) =>
                                            '${s?.available ?? 0}'),
                                    TableColumn<StockLine?>(
                                        label: 'الحالة',
                                        value: (s) => (s?.available ?? 0) <=
                                                0
                                            ? 'نافد'
                                            : 'متاح'),
                                  ],
                                  rows: lines,
                                  cardBuilder: (s) =>
                                      AppCard(
                                    padding:
                                        const EdgeInsets
                                            .all(
                                                AppSpacing
                                                    .md),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start,
                                            children: [
                                              Text(
                                                  s?.productName ?? '',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall,
                                                  maxLines:
                                                      1,
                                                  overflow:
                                                      TextOverflow
                                                          .ellipsis),
                                              Text(
                                                '${s?.productSku ?? ''} • متاح ${s?.available ?? 0}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                                textDirection:
                                                    TextDirection
                                                        .ltr,
                                              ),
                                            ],
                                          ),
                                        ),
                                        StatusBadge(
                                          label: (s?.available ?? 0) <=
                                                  0
                                              ? 'نافد'
                                              : 'متاح',
                                          tone: (s?.available ?? 0) <=
                                                  0
                                              ? StatusTone
                                                  .rejected
                                              : StatusTone
                                                  .approved,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      moves.when(
                        loading: () =>
                            const LoadingSkeleton(
                                rows: 5),
                        error: (_, _) =>
                            const ErrorState(
                                message:
                                    'تعذر تحميل الحركات.'),
                        data: (list) {
                          if (list.isEmpty) {
                            return const EmptyState(
                              icon: Icons
                                  .swap_horiz_outlined,
                              title: 'لا توجد حركات',
                              subtitle:
                                  'كل تغيير مخزون يظهر هنا',
                            );
                          }
                          return ListView(
                            children: [
                              ResponsiveTable<StockMovement?>(
                                columns: [
                                  TableColumn<StockMovement?>(
                                      label: 'النوع',
                                      value: (m) =>
                                          _moveAr(
                                              m?.type ?? '')),
                                  TableColumn<StockMovement?>(
                                      label: 'الكمية',
                                      numeric: true,
                                      value: (m) =>
                                          '${m?.quantity ?? 0}'),
                                  TableColumn<StockMovement?>(
                                      label: 'قبل',
                                      numeric: true,
                                      value: (m) =>
                                          '${m?.beforeQty ?? 0}'),
                                  TableColumn<StockMovement?>(
                                      label: 'بعد',
                                      numeric: true,
                                      value: (m) =>
                                          '${m?.afterQty ?? 0}'),
                                  TableColumn<StockMovement?>(
                                      label: 'التاريخ',
                                      value: (m) =>
                                          AppFormat.date(
                                              m?.createdAt ?? DateTime.now())),
                                ],
                                rows: list,
                                cardBuilder: (m) =>
                                    AppCard(
                                  padding:
                                      const EdgeInsets
                                          .all(
                                              AppSpacing
                                                  .md),
                                  child: Row(
                                    children: [
                                      Icon(
                                          (m?.type ?? '').endsWith(
                                                  'IN')
                                              ? Icons
                                                  .arrow_downward_outlined
                                              : Icons
                                                  .arrow_upward_outlined,
                                          size: 20),
                                      const SizedBox(
                                          width:
                                              AppSpacing
                                                  .sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                                '${_moveAr(m?.type ?? '')} • ${m?.quantity ?? 0}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall),
                                            Text(
                                              'قبل ${m?.beforeQty ?? 0} ← بعد ${m?.afterQty ?? 0}${m?.notes != null ? ' • ${m?.notes}' : ''}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                              maxLines:
                                                  2,
                                              overflow:
                                                  TextOverflow
                                                      .ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      );
  }

  static String _moveAr(String type) {
    return const {
      'PURCHASE': 'شراء',
      'SALE': 'بيع',
      'PURCHASE_RETURN': 'مرتجع مشتريات',
      'SALES_RETURN': 'مرتجع مبيعات',
      'ADJUSTMENT_IN': 'تسوية إدخال',
      'ADJUSTMENT_OUT': 'تسوية إخراج',
      'TRANSFER_IN': 'تحويل وارد',
      'TRANSFER_OUT': 'تحويل صادر',
      'MANUFACTURING_IN': 'إنتاج وارد',
      'MANUFACTURING_OUT': 'صرف تصنيع',
    }[type] ??
        type;
  }


  Future<void> _deleteWarehouse(BuildContext context, WidgetRef ref,
      String id, String name) async {
    if (!await confirmDelete(context, 'المخزن "$name"')) return;
    try {
      await ref.read(warehousesRepositoryProvider).deleteWarehouse(id);
      ref
        ..invalidate(warehousesListProvider)
        ..invalidate(warehouseDetailProvider(id));
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(deleteErrorMessage(e))));
      }
    }
  }

  void _adjustSheet(
      BuildContext context, WidgetRef ref, String wid) {
    final qty = TextEditingController();
    final notes = TextEditingController();
    String? productId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ProductPicker(
        title: 'تسوية مخزون (موجب إدخال / سالب إخراج)',
        onPick: (id) => productId = id,
        actionLabel: 'تنفيذ التسوية',
        onAction: () async {
          final change = double.tryParse(qty.text.trim());
          if (productId == null || change == null || change == 0) {
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content:
                    Text('اختر المنتج وأدخل كمية غير صفرية.')));
            return;
          }
          try {
            await ref.read(warehousesRepositoryProvider).adjust(
                warehouseId: wid,
                productId: productId!,
                qtyChange: change,
                notes: notes.text.trim().isEmpty
                    ? null
                    : notes.text.trim());
            ref
              ..invalidate(warehouseStockProvider(wid))
              ..invalidate(warehouseMovementsProvider(wid))
              ..invalidate(inventoryOverviewProvider);
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(e is AppFailure
                      ? e.messageAr
                      : 'حدث خطأ أثناء تنفيذ العملية.')));
            }
          }
        },
        extra: Column(children: [
          TextField(
              controller: qty,
              keyboardType:
                  const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'التغير (+10 / -5)')),
          TextField(
              controller: notes,
              decoration:
                  const InputDecoration(labelText: 'ملاحظات')),
        ]),
      ),
    );
  }

  void _transferSheet(
      BuildContext context, WidgetRef ref, String fromId) {
    final qty = TextEditingController();
    final notes = TextEditingController();
    String? productId;
    String? toId;
    final warehouses =
        ref.read(warehousesListProvider).maybeWhen(
              data: (w) => w.where((e) => e.id != fromId).toList(),
              orElse: () => [],
            );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تحويل لمخزن آخر',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: 'المخزن المستلم'),
                items: [
                  for (final w in warehouses)
                    DropdownMenuItem(
                        value: w.id,
                        child: Text('${w.name} (${w.code})')),
                ],
                onChanged: (v) => setS(() => toId = v),
              ),
              _ProductPickerBody(onPick: (id) => productId = id),
              TextField(
                  controller: qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration:
                      const InputDecoration(labelText: 'الكمية')),
              TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظات')),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final q = double.tryParse(qty.text.trim());
                  if (productId == null ||
                      toId == null ||
                      q == null ||
                      q <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'اختر المنتج والمخزن وأدخل كمية صحيحة.')));
                    return;
                  }
                  try {
                    await ref
                        .read(warehousesRepositoryProvider)
                        .transfer(
                            fromWarehouse: fromId,
                            toWarehouse: toId!,
                            productId: productId!,
                            quantity: q,
                            notes: notes.text.trim().isEmpty
                                ? null
                                : notes.text.trim());
                    ref
                      ..invalidate(
                          warehouseStockProvider(fromId))
                      ..invalidate(
                          warehouseMovementsProvider(fromId))
                      ..invalidate(inventoryOverviewProvider);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text(e is AppFailure
                                  ? e.messageAr
                                  : 'حدث خطأ — تحقق من الرصيد المتاح.')));
                    }
                  }
                },
                child: const Text('تنفيذ التحويل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  final String title;
  final void Function(String id) onPick;
  final String actionLabel;
  final Future<void> Function() onAction;
  final Widget extra;
  const _ProductPicker(
      {required this.title,
      required this.onPick,
      required this.actionLabel,
      required this.onAction,
      required this.extra});

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  final _search = TextEditingController();
  List<Product> _results = [];
  String? _picked;
  bool _busy = false;

  Future<void> _find() async {
    setState(() => _busy = true);
    try {
      _results = await ref
          .read(productsRepositoryProvider)
          .search(query: _search.text, pageSize: 20);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold)),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                        labelText: 'بحث منتج بالاسم/SKU/باركود'))),
            IconButton(
                onPressed: _find,
                icon: const Icon(Icons.search_outlined)),
          ]),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            RadioGroup<String?>(
              groupValue: _picked,
              onChanged: (v) {
                setState(() => _picked = v);
                if (v != null) widget.onPick(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in _results)
                    RadioListTile<String?>(
                      value: p.id,
                      title: Text(p.name),
                      subtitle: Text(p.sku,
                          textDirection: TextDirection.ltr),
                    ),
                ],
              ),
            ),
          widget.extra,
          const SizedBox(height: 8),
          FilledButton(
              onPressed: widget.onAction,
              child: Text(widget.actionLabel)),
        ],
      ),
    );
  }
}

class _ProductPickerBody extends ConsumerStatefulWidget {
  final void Function(String id) onPick;
  const _ProductPickerBody({required this.onPick});

  @override
  ConsumerState<_ProductPickerBody> createState() =>
      _ProductPickerBodyState();
}

class _ProductPickerBodyState extends ConsumerState<_ProductPickerBody> {
  final _search = TextEditingController();
  List<Product> _results = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(
            child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                    labelText: 'بحث منتج'))),
        IconButton(
          icon: const Icon(Icons.search_outlined),
          onPressed: () async {
            _results = await ref
                .read(productsRepositoryProvider)
                .search(query: _search.text, pageSize: 20);
            setState(() {});
          },
        ),
      ]),
      for (final p in _results)
        ListTile(
          title: Text(p.name),
          subtitle:
              Text(p.sku, textDirection: TextDirection.ltr),
          trailing: TextButton(
              onPressed: () => widget.onPick(p.id),
              child: const Text('اختيار')),
        ),
    ]);
  }
}
