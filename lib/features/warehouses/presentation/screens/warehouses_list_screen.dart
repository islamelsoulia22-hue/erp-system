import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permissions.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/responsive_table.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/warehouse.dart';
import '../providers/warehouses_providers.dart';

class WarehousesListScreen extends ConsumerStatefulWidget {
  const WarehousesListScreen({super.key});

  @override
  ConsumerState<WarehousesListScreen> createState() =>
      _WarehousesListScreenState();
}

class _WarehousesListScreenState
    extends ConsumerState<WarehousesListScreen> {
  int _page = 0;

  void _go(int p) => setState(() => _page = p);

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(warehousesListProvider);
    final canManage = ref.watch(myPermissionsProvider).maybeWhen(
          data: (p) => p.can(Permissions.warehousesManage),
          orElse: () => false,
        );

    return ResponsiveLayout(
      mobile: RefreshIndicator(
        onRefresh: () async {
          setState(() => _page = 0);
          ref.invalidate(warehousesListProvider);
        },
        child: ListView(
          padding:
              EdgeInsets.all(context.contentPadding),
          children: [
            if (canManage)
              Align(
                alignment:
                    AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: () =>
                      context.push('/warehouses/new'),
                  icon: const Icon(Icons.add_outlined,
                      size: 18),
                  label: const Text('مخزن جديد'),
                ),
              ),
            if (canManage)
              const SizedBox(height: AppSpacing.md),
            list.when(
              loading: () =>
                  const LoadingSkeleton(rows: 4),
              error: (_, _) => const ErrorState(),
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.warehouse_outlined,
                    title: 'لا توجد مخازن بعد',
                  );
                }
                final items =
                    paginateLocal(rows, _page);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    ResponsiveTable<Warehouse>(
                      columns: [
                        TableColumn(
                            label: 'المخزن',
                            value: (w) => w.name),
                        TableColumn(
                            label: 'الكود',
                            value: (w) => w.code),
                        TableColumn(
                            label: 'الموقع',
                            value: (w) =>
                                w.location ?? '—'),
                        TableColumn(
                            label: 'الحالة',
                            value: (w) => w.isActive
                                ? 'نشط'
                                : 'موقوف'),
                      ],
                      rows: items,
                      onTap: (w) => context
                          .push('/warehouses/${w.id}'),
                      cardBuilder: (w) => AppCard(
                        onTap: () => context.push(
                            '/warehouses/${w.id}'),
                        padding: const EdgeInsets.all(
                            AppSpacing.md),
                        child: Row(
                          children: [
                            const Icon(
                                Icons.warehouse_outlined,
                                size: 22),
                            const SizedBox(
                                width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Text(w.name,
                                      style:
                                          Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                  Text(
                                    '${w.code}${w.location != null ? ' • ${w.location}' : ''}',
                                    style: Theme.of(
                                            context)
                                        .textTheme
                                        .bodySmall,
                                    textDirection:
                                        TextDirection.ltr,
                                  ),
                                ],
                              ),
                            ),
                            if (!w.isActive)
                              AppStatus.badge(
                                  'INACTIVE'),
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
