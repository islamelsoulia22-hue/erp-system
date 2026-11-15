import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/warehouse.dart';
import '../providers/warehouses_providers.dart';

/// Inventory dashboard: summary strip, warehouse filter, search
/// and a stock table (cards on mobile).
class InventoryOverviewScreen extends ConsumerStatefulWidget {
  const InventoryOverviewScreen({super.key});

  @override
  ConsumerState<InventoryOverviewScreen> createState() =>
      _InventoryOverviewScreenState();
}

class _InventoryOverviewScreenState
    extends ConsumerState<InventoryOverviewScreen> {
  final _search = TextEditingController();
  String? _warehouseId;
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  void _resetPage() {
    if (_page != 0) setState(() => _page = 0);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(inventoryOverviewProvider);
    final warehouses = ref.watch(warehousesListProvider);

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(inventoryOverviewProvider),
        child: ListView(
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            AppCard(
              child: Column(
                children: [
                  SearchField(
                    controller: _search,
                    hint: 'بحث بمنتج أو مخزن',
                    onSubmitted: (v) {
                      ref
                          .read(inventorySearchProvider
                              .notifier)
                          .state = v;
                      _resetPage();
                      setState(() {});
                    },
                    onClear: () {
                      ref
                          .read(inventorySearchProvider
                              .notifier)
                          .state = '';
                      _resetPage();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  warehouses.maybeWhen(
                    data: (rows) =>
                        DropdownButtonFormField<
                            String?>(
                      initialValue: _warehouseId,
                      decoration:
                          const InputDecoration(
                              labelText: 'المخزن',
                              prefixIcon: Icon(
                                  Icons.warehouse_outlined,
                                  size: 18)),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child:
                                Text('كل المخازن')),
                        for (final w in rows)
                          DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name,
                                  overflow:
                                      TextOverflow
                                          .ellipsis)),
                      ],
                      onChanged: (v) => setState(() {
                        _warehouseId = v;
                        _page = 0;
                      }),
                    ),
                    orElse: () =>
                        const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            overview.when(
              loading: () =>
                  const LoadingSkeleton(rows: 6),
              error: (_, _) => const ErrorState(),
              data: (lines) {
                final rows = _warehouseId == null
                    ? lines
                    : lines
                        .where((s) =>
                            s.warehouseId ==
                            _warehouseId)
                        .toList();
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_outlined,
                    title: 'لا يوجد رصيد',
                    subtitle:
                        'ابحث باسم مختلف أو اختر مخزنا آخر',
                  );
                }
                final out =
                    rows.where((s) => s.available <= 0);
                return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _MiniStat(
                                label: 'بنود',
                                value: '${rows.length}',
                                icon: Icons
                                    .inventory_2_outlined,
                                color: AppColors
                                    .primary)),
                        const SizedBox(
                            width: AppSpacing.sm),
                        Expanded(
                            child: _MiniStat(
                                label: 'نافد',
                                value: '${out.length}',
                                icon: Icons
                                    .warning_amber_outlined,
                                color: AppColors.danger)),
                      ],
                    ),
                    const SizedBox(
                        height: AppSpacing.md),
                    ResponsiveTable<StockLine>(
                      columns: const [
                        TableColumn(
                            label: 'المنتج',
                            value: _pName),
                        TableColumn(
                            label: 'SKU',
                            value: _pSku),
                        TableColumn(
                            label: 'المخزن',
                            value: _pWh),
                        TableColumn(
                            label: 'المتاح',
                            numeric: true,
                            value: _pAv),
                        TableColumn(
                            label: 'الحالة',
                            value: _pState),
                      ],
                      rows: paginateLocal(rows, _page),
                      cardBuilder: (s) => AppCard(
                        padding:
                            const EdgeInsets.all(
                                AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(s.productName,
                                      style:
                                          Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow
                                              .ellipsis),
                                  Text(
                                    '${s.warehouseName} • ${s.productSku}',
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .bodySmall,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                  ),
                                  Text(
                                    'متاح ${s.available}',
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                            ),
                            StatusBadge(
                              label: s.available <= 0
                                  ? 'نافد'
                                  : 'متاح',
                              tone: s.available <= 0
                                  ? StatusTone.rejected
                                  : StatusTone.approved,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AppPagination(
                      page: _page,
                      total: rows.length,
                      onGo: _go,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _pName(StockLine s) => s.productName;
String _pSku(StockLine s) => s.productSku;
String _pWh(StockLine s) => s.warehouseName;
String _pAv(StockLine s) => '${s.available}';
String _pState(StockLine s) =>
    s.available <= 0 ? 'نافد' : 'متاح';

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding:
          const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
