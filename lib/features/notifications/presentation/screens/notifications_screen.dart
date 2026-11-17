import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_pagination.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/yad_widgets.dart';
import '../../../procurement/data/procurement_repository.dart';
import '../../../procurement/domain/procurement.dart';

/// الإشعارات بتصميم YAD: فلاتر دائرية + بطاقات بحافة ملونة
/// (حمراء للنقص، Indigo للمستندات، بدون حافة للمقروء).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  int _page = 0;
  int _filter = 0; // 0 الكل، 1 جديدة، 2 مقروءة

  void _go(int p) => setState(() => _page = p);

  void _open(BuildContext context, AppNotification n) {
    final entity = n.entityType;
    final id = n.entityId;
    if (entity == 'PROCUREMENT_REQUEST' && id != null) {
      context.push('/procurement/$id');
    } else if (entity == 'STOCK_ALERT') {
      context.push('/stock-alerts');
    }
  }

  Future<void> _refresh() async {
    setState(() => _page = 0);
    ref.invalidate(notificationsListProvider);
    ref.invalidate(unreadCountProvider);
  }

  /// (أيقونة، لون الأيقونة، خلفيتها، لون الحافة).
  (IconData, Color, Color, Color?) _look(AppNotification n) {
    if (n.isRead) {
      return (
        Icons.notifications_none_outlined,
        AppColors.neutral,
        AppColors.neutralContainer,
        null
      );
    }
    switch (n.entityType) {
      case 'STOCK_ALERT':
        return (
          Icons.warning_amber_outlined,
          AppColors.danger,
          AppColors.dangerContainer,
          AppColors.coral
        );
      case 'PROCUREMENT_REQUEST':
        return (
          Icons.fact_check_outlined,
          AppColors.indigoDeep,
          AppColors.primaryContainer,
          AppColors.indigo
        );
      default:
        return (
          Icons.notifications_active_outlined,
          AppColors.success,
          AppColors.successContainer,
          AppColors.mint
        );
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
    if (d.inDays == 1) return 'أمس';
    if (d.inDays < 7) return 'منذ ${d.inDays} أيام';
    return AppFormat.date(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(notificationsListProvider);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: list.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(16), child: LoadingSkeleton(rows: 5)),
        error: (_, _) => ErrorState(onRetry: _refresh),
        data: (all) {
          final rows = switch (_filter) {
            1 => all.where((n) => !n.isRead).toList(),
            2 => all.where((n) => n.isRead).toList(),
            _ => all,
          };
          final items = paginateLocal(rows, _page);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: YadFilterBar(
                      labels: const ['الكل', 'جديدة', 'مقروءة'],
                      selected: _filter,
                      onChanged: (i) => setState(() {
                        _filter = i;
                        _page = 0;
                      }),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: all.every((n) => n.isRead)
                      ? null
                      : () async {
                          await ref
                              .read(notificationsRepositoryProvider)
                              .markAllRead();
                          ref.invalidate(notificationsListProvider);
                          ref.invalidate(unreadCountProvider);
                        },
                  icon: const Icon(Icons.done_all_outlined, size: 18),
                  label: const Text('تعيين الكل كمقروء'),
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: 'لا توجد إشعارات',
                  ),
                ),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RiseIn(
                    index: i,
                    child: _card(context, theme, items[i]),
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
    );
  }

  Widget _card(
      BuildContext context, ThemeData theme, AppNotification n) {
    final (icon, fg, bg, edge) = _look(n);
    return TapScale(
      semanticLabel: n.title,
      onTap: () async {
        if (!n.isRead) {
          await ref.read(notificationsRepositoryProvider).markRead(n.id);
          ref.invalidate(notificationsListProvider);
          ref.invalidate(unreadCountProvider);
        }
        if (context.mounted) _open(context, n);
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? AppColors.darkDivider
                  : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: edge ?? Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    YadIconTile(
                        icon: icon,
                        color: fg,
                        background: bg,
                        size: 44,
                        radius: 15),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: n.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800)),
                          if ((n.message ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(n.message!,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                          color: AppColors.secondaryText,
                                          height: 1.5)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_ago(n.createdAt),
                                style: theme.textTheme.labelSmall),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
