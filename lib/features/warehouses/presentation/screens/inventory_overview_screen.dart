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
import '../../../../core/widgets/yad_widgets.dart';
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
                final maxAvail = rows.fold<double>(
                    1,
                    (m, s) => s.available.toDouble() > m
                        ? s.available.toDouble()
                        : m);
                return Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            label: 'عدد البنود',
                            value: '${rows.length}',
                            dark: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatTile(
                            label: 'نافد',
                            value: '${out.length}',
                            badge: out.isEmpty ? 'ممتاز' : 'يحتاج توريد',
                            badgeOk: out.isEmpty,
                          ),
                        ),
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
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(s.productName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis),
                                      Text(
                                        '${s.productSku} • ${s.warehouseName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
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
                            const SizedBox(height: 14),
                            _StockBar(
                              value: s.available.toDouble(),
                              max: maxAvail,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الكمية المتاحة',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: AppColors
                                                .secondaryText)),
                                Text('${s.available} وحدة',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                              ],
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

/// بلاطة إحصاء: الداكنة (Midnight→Navy) أو البيضاء مع شارة حالة.
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool dark;
  final String? badge;
  final bool badgeOk;
  const _StatTile({
    required this.label,
    required this.value,
    this.dark = false,
    this.badge,
    this.badgeOk = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = dark ? Colors.white : theme.colorScheme.onSurface;
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
                color: dark
                    ? AppColors.heroSoft
                    : AppColors.secondaryText)),
        Row(
          children: [
            Text(value,
                style: theme.textTheme.displayMedium
                    ?.copyWith(color: fg, fontSize: 34, height: 1.25)),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: StatusBadge(
                  label: badge!,
                  tone: badgeOk
                      ? StatusTone.approved
                      : StatusTone.rejected,
                ),
              ),
            ],
          ],
        ),
      ],
    );
    if (dark) {
      return YadHeroCard(
          padding: const EdgeInsets.all(16), child: inner);
    }
    return AppCard(padding: const EdgeInsets.all(16), child: inner);
  }
}

/// شريط الكمية: يتحرك من الصفر للقيمة (1s) بتدرج Mint→Sky،
/// والنافد بلون Coral. النسبة مقارنة بأعلى رصيد في القائمة.
class _StockBar extends StatelessWidget {
  final double value;
  final double max;
  const _StockBar({required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    final out = value <= 0;
    return Container(
      height: 9,
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF8),
        borderRadius: BorderRadius.circular(99),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: AlignmentDirectional.centerStart,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: out ? 1 : ratio),
        duration: yadDuration(context, 1000),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                colors: out
                    ? const [AppColors.coral, AppColors.coral]
                    : const [AppColors.mint, AppColors.sky],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
